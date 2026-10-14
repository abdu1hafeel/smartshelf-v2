-- ==============================================================================
-- SmartShelf V2 - Shop Invitations & Unified Onboarding
-- Migration: 20261015020000_shop_invitations_and_onboarding.sql
--
-- SECURITY & INTEGRITY INVARIANTS:
-- 1. Secure Invitations: Single-use or multi-use time-bounded invite tokens.
-- 2. Role Restriction: Only Shop Admins or Org Admins can issue invitations.
-- 3. No Self-Elevation: Public registration cannot arbitrarily claim roles or shops.
-- 4. Atomic Onboarding: Creation of organization, shop, and administrative memberships
--    in a single atomic transaction preventing orphaned or half-created tenants.
-- ==============================================================================

-- 1. Create shop_invitations table
CREATE TABLE IF NOT EXISTS public.shop_invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    invite_code text NOT NULL UNIQUE,
    role text NOT NULL CHECK (role IN ('SHOP_ADMIN', 'SHOPKEEPER')),
    invited_email text,
    max_uses integer NOT NULL DEFAULT 1 CHECK (max_uses > 0),
    uses_count integer NOT NULL DEFAULT 0 CHECK (uses_count <= max_uses),
    expires_at timestamptz NOT NULL,
    is_revoked boolean NOT NULL DEFAULT false,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_shop_invitations_lookup 
ON public.shop_invitations(invite_code, is_revoked, expires_at);

CREATE INDEX IF NOT EXISTS idx_shop_invitations_shop 
ON public.shop_invitations(shop_id);

-- Enable RLS on shop_invitations
ALTER TABLE public.shop_invitations ENABLE ROW LEVEL SECURITY;

-- Policy: Shop admins and Org admins can view invitations for their shop
CREATE POLICY "shop_invitations_admin_select" ON public.shop_invitations
FOR SELECT
TO authenticated
USING (public.is_shop_admin(shop_id));

-- Policy: Disallow direct client INSERT/UPDATE/DELETE (enforce through SECURITY DEFINER RPCs)
CREATE POLICY "shop_invitations_direct_disallowed" ON public.shop_invitations
FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- 2. RPC: Create Shop Invitation
CREATE OR REPLACE FUNCTION public.create_shop_invitation(
    p_shop_id uuid,
    p_role text DEFAULT 'SHOPKEEPER',
    p_invited_email text DEFAULT NULL,
    p_max_uses integer DEFAULT 1,
    p_validity_days integer DEFAULT 7
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _code text;
    _expires_at timestamptz;
    _invitation_id uuid;
    _shop_name text;
    _clean_email text;
BEGIN
    -- 1. Authentication check
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    -- 2. Authorization check: Only Shop Admin or Org Admin can generate invitations
    IF NOT public.is_shop_admin(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop Administrator can create store invitations';
    END IF;

    -- 3. Role check
    IF p_role NOT IN ('SHOP_ADMIN', 'SHOPKEEPER') THEN
        RAISE EXCEPTION 'Invalid role: Must be SHOP_ADMIN or SHOPKEEPER';
    END IF;

    IF p_max_uses <= 0 THEN
        RAISE EXCEPTION 'Invalid max_uses: Must be at least 1';
    END IF;

    IF p_validity_days <= 0 THEN
        RAISE EXCEPTION 'Invalid validity: Must be at least 1 day';
    END IF;

    SELECT name INTO _shop_name FROM public.shops WHERE id = p_shop_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop not found';
    END IF;

    -- 4. Generate random readable code format: SH-XXXX-YYYY
    _code := 'SH-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 4)) || '-' || upper(substr(md5(random()::text || clock_timestamp()::text), 5, 4));
    _expires_at := clock_timestamp() + (p_validity_days || ' days')::interval;
    _clean_email := NULLIF(lower(trim(p_invited_email)), '');

    INSERT INTO public.shop_invitations (
        id, shop_id, invite_code, role, invited_email,
        max_uses, uses_count, expires_at, is_revoked,
        created_by, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), p_shop_id, _code, p_role, _clean_email,
        p_max_uses, 0, _expires_at, false,
        auth.uid(), clock_timestamp(), clock_timestamp()
    ) RETURNING id INTO _invitation_id;

    RETURN jsonb_build_object(
        'invitation_id', _invitation_id,
        'shop_id', p_shop_id,
        'shop_name', _shop_name,
        'invite_code', _code,
        'role', p_role,
        'invited_email', _clean_email,
        'max_uses', p_max_uses,
        'expires_at', _expires_at
    );
END;
$$;

-- 3. RPC: Redeem Shop Invitation
CREATE OR REPLACE FUNCTION public.redeem_shop_invitation(
    p_invite_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _inv public.shop_invitations%ROWTYPE;
    _caller_email text;
    _shop_name text;
    _org_id uuid;
    _membership_id uuid;
BEGIN
    -- 1. Authentication check
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required to redeem invitation';
    END IF;

    IF trim(p_invite_code) IS NULL OR length(trim(p_invite_code)) = 0 THEN
        RAISE EXCEPTION 'Invitation code cannot be empty';
    END IF;

    -- 2. Lookup invitation with row lock to prevent concurrency race conditions
    SELECT * INTO _inv
    FROM public.shop_invitations
    WHERE upper(trim(invite_code)) = upper(trim(p_invite_code))
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid invitation code: Code does not exist';
    END IF;

    -- 3. Validation checks
    IF _inv.is_revoked THEN
        RAISE EXCEPTION 'This invitation code has been revoked by the store administrator';
    END IF;

    IF _inv.expires_at < clock_timestamp() THEN
        RAISE EXCEPTION 'This invitation code has expired';
    END IF;

    IF _inv.uses_count >= _inv.max_uses THEN
        RAISE EXCEPTION 'This invitation code has already reached its maximum usage limit';
    END IF;

    -- 4. Check targeted email restriction if set
    _caller_email := lower(trim(COALESCE(auth.jwt()->>'email', '')));
    IF _inv.invited_email IS NOT NULL AND _caller_email != lower(trim(_inv.invited_email)) THEN
        RAISE EXCEPTION 'This invitation was issued for %, but you are signed in as %', _inv.invited_email, _caller_email;
    END IF;

    -- 5. Resolve Shop info
    SELECT s.name, s.organization_id INTO _shop_name, _org_id
    FROM public.shops s
    WHERE s.id = _inv.shop_id;

    -- 6. Atomically assign shop membership
    INSERT INTO public.shop_memberships (
        id, shop_id, user_id, role, status, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), _inv.shop_id, auth.uid(), _inv.role, 'ACTIVE', clock_timestamp(), clock_timestamp()
    )
    ON CONFLICT (shop_id, user_id) DO UPDATE
    SET role = EXCLUDED.role,
        status = 'ACTIVE',
        updated_at = clock_timestamp()
    RETURNING id INTO _membership_id;

    -- 7. Increment usage count
    UPDATE public.shop_invitations
    SET uses_count = uses_count + 1,
        updated_at = clock_timestamp()
    WHERE id = _inv.id;

    RETURN jsonb_build_object(
        'success', true,
        'membership_id', _membership_id,
        'shop_id', _inv.shop_id,
        'shop_name', _shop_name,
        'organization_id', _org_id,
        'role', _inv.role
    );
END;
$$;

-- 4. RPC: Atomic Organization & Shop Onboarding (Option B)
CREATE OR REPLACE FUNCTION public.create_organization_and_shop(
    p_org_name text,
    p_shop_name text,
    p_location text DEFAULT NULL,
    p_currency text DEFAULT 'INR'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _org_id uuid;
    _shop_id uuid;
    _org_membership_id uuid;
    _shop_membership_id uuid;
    _clean_org text;
    _clean_shop text;
    _clean_currency text;
BEGIN
    -- 1. Authentication check
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required to create a store';
    END IF;

    _clean_org := trim(p_org_name);
    _clean_shop := trim(p_shop_name);
    _clean_currency := coalesce(nullif(upper(trim(p_currency)), ''), 'INR');

    IF _clean_org IS NULL OR length(_clean_org) < 2 THEN
        RAISE EXCEPTION 'Invalid organization name: Must be at least 2 characters';
    END IF;

    IF _clean_shop IS NULL OR length(_clean_shop) < 2 THEN
        RAISE EXCEPTION 'Invalid shop name: Must be at least 2 characters';
    END IF;

    -- 2. Create organization
    INSERT INTO public.organizations (id, name, created_at, updated_at)
    VALUES (gen_random_uuid(), _clean_org, clock_timestamp(), clock_timestamp())
    RETURNING id INTO _org_id;

    -- 3. Assign caller as ORG_ADMIN
    INSERT INTO public.organization_memberships (
        id, organization_id, user_id, role, status, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), _org_id, auth.uid(), 'ORG_ADMIN', 'ACTIVE', clock_timestamp(), clock_timestamp()
    ) RETURNING id INTO _org_membership_id;

    -- 4. Create primary shop
    INSERT INTO public.shops (
        id, organization_id, name, location, currency, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), _org_id, _clean_shop, nullif(trim(p_location), ''), _clean_currency, clock_timestamp(), clock_timestamp()
    ) RETURNING id INTO _shop_id;

    -- 5. Initialize shop receipt sequence
    INSERT INTO public.shop_receipt_sequences (shop_id, last_number, updated_at)
    VALUES (_shop_id, 0, clock_timestamp())
    ON CONFLICT (shop_id) DO NOTHING;

    -- 6. Assign caller as SHOP_ADMIN for direct shop access
    INSERT INTO public.shop_memberships (
        id, shop_id, user_id, role, status, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), _shop_id, auth.uid(), 'SHOP_ADMIN', 'ACTIVE', clock_timestamp(), clock_timestamp()
    ) RETURNING id INTO _shop_membership_id;

    RETURN jsonb_build_object(
        'success', true,
        'organization_id', _org_id,
        'organization_name', _clean_org,
        'shop_id', _shop_id,
        'shop_name', _clean_shop,
        'currency', _clean_currency,
        'role', 'SHOP_ADMIN'
    );
END;
$$;

-- Grant execute permissions to authenticated and service_role
GRANT EXECUTE ON FUNCTION public.create_shop_invitation(uuid, text, text, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.redeem_shop_invitation(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_organization_and_shop(text, text, text, text) TO authenticated, service_role;
