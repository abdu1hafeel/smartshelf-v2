-- ==============================================================================
-- SmartShelf V2 - Migration: Explicit extensions namespace for pgcrypto functions
-- Migration: 20261014201000_fix_pgcrypto_search_path.sql
--
-- ARCHITECTURAL RATIONALE:
-- In Supabase, the pgcrypto extension is installed in the extensions schema.
-- Updating search_path to (public, extensions, pg_catalog) and qualifying
-- gen_random_bytes and digest ensures cryptographic operations succeed seamlessly.
-- ==============================================================================

-- 1. enroll_device
CREATE OR REPLACE FUNCTION public.enroll_device(
    p_shop_id uuid,
    p_device_identifier text,
    p_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_catalog
AS $$
DECLARE
    _device_id uuid := gen_random_uuid();
    _secret_raw text;
    _secret_hash text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_shop_admin(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can enroll devices';
    END IF;

    IF trim(p_device_identifier) IS NULL OR length(trim(p_device_identifier)) < 3 THEN
        RAISE EXCEPTION 'Invalid device identifier';
    END IF;

    -- Generate 256-bit cryptographically secure random secret token
    _secret_raw := encode(extensions.gen_random_bytes(32), 'hex');
    _secret_hash := encode(extensions.digest(_secret_raw, 'sha256'), 'hex');

    INSERT INTO public.devices (
        id, shop_id, device_identifier, name, calibration_factor,
        tare_offset, last_sequence_number, is_active, created_at, updated_at
    ) VALUES (
        _device_id, p_shop_id, trim(p_device_identifier), trim(p_name), 1.0000,
        0.0000, 0, true, clock_timestamp(), clock_timestamp()
    );

    INSERT INTO public.device_credentials (device_id, api_key_hash, created_at, updated_at)
    VALUES (_device_id, _secret_hash, clock_timestamp(), clock_timestamp());

    -- Secret is returned ONCE to the enrolling administrator
    RETURN jsonb_build_object(
        'device_id', _device_id,
        'shop_id', p_shop_id,
        'device_identifier', trim(p_device_identifier),
        'device_secret', _secret_raw,
        'warning', 'Store this device secret safely. It will not be shown again.'
    );
END;
$$;

-- 2. rotate_device_credentials
CREATE OR REPLACE FUNCTION public.rotate_device_credentials(
    p_device_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_catalog
AS $$
DECLARE
    _shop_id uuid;
    _secret_raw text;
    _secret_hash text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    SELECT shop_id INTO _shop_id FROM public.devices WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Device % not found', p_device_id;
    END IF;

    IF NOT public.is_shop_admin(_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can rotate device credentials';
    END IF;

    _secret_raw := encode(extensions.gen_random_bytes(32), 'hex');
    _secret_hash := encode(extensions.digest(_secret_raw, 'sha256'), 'hex');

    UPDATE public.device_credentials
    SET api_key_hash = _secret_hash,
        updated_at = clock_timestamp()
    WHERE device_id = p_device_id;

    UPDATE public.devices
    SET updated_at = clock_timestamp()
    WHERE id = p_device_id;

    RETURN jsonb_build_object(
        'device_id', p_device_id,
        'new_device_secret', _secret_raw,
        'warning', 'Device secret rotated. Update the firmware credentials.'
    );
END;
$$;

-- 3. recover_device_after_reset
CREATE OR REPLACE FUNCTION public.recover_device_after_reset(
    p_device_id uuid,
    p_epoch_offset bigint DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_catalog
AS $$
DECLARE
    _device_record record;
    _new_epoch bigint;
    _secret_raw text;
    _secret_hash text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    SELECT d.id, d.shop_id, d.current_epoch, d.is_active
    INTO _device_record
    FROM public.devices d
    WHERE d.id = p_device_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Device % not found', p_device_id;
    END IF;

    IF NOT public.is_shop_admin(_device_record.shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can perform device recovery';
    END IF;

    IF p_epoch_offset IS NOT NULL AND p_epoch_offset <= 0 THEN
        RAISE EXCEPTION 'Epoch offset must be a positive integer';
    END IF;

    _new_epoch := _device_record.current_epoch + coalesce(p_epoch_offset, 10);

    _secret_raw := encode(extensions.gen_random_bytes(32), 'hex');
    _secret_hash := encode(extensions.digest(_secret_raw, 'sha256'), 'hex');

    UPDATE public.device_credentials
    SET api_key_hash = _secret_hash,
        updated_at = clock_timestamp()
    WHERE device_id = p_device_id;

    UPDATE public.devices
    SET current_epoch = _new_epoch,
        last_sequence_number = 0,
        is_active = true,
        updated_at = clock_timestamp()
    WHERE id = p_device_id;

    RETURN jsonb_build_object(
        'device_id', p_device_id,
        'new_epoch', _new_epoch,
        'new_device_secret', _secret_raw,
        'warning', 'Epoch advanced and new secret generated. Update device firmware.'
    );
END;
$$;

-- Explicit grants to authenticated
GRANT EXECUTE ON FUNCTION public.enroll_device(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rotate_device_credentials(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recover_device_after_reset(uuid, bigint) TO authenticated;
