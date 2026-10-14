-- ==============================================================================
-- SmartShelf V2 - Migration: Add Secure Category Provisioning Procedure
-- Migration: 20261014200000_create_category_rpc.sql
--
-- ARCHITECTURAL RATIONALE:
-- Follows the engine-level zero-trust privilege model established in the base migration.
-- Direct table-level INSERT on public.categories remains revoked.
-- Mutations strictly flow through this SECURITY DEFINER procedure with verified ORG_ADMIN authorization.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.create_category(
    p_organization_id uuid,
    p_name text,
    p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _category_id uuid;
BEGIN
    -- 1. Authentication check
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    -- 2. Organization admin authorization check
    IF NOT public.is_org_admin(p_organization_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only an active ORG_ADMIN can create product categories';
    END IF;

    -- 3. Name validation
    IF trim(p_name) IS NULL OR length(trim(p_name)) < 1 THEN
        RAISE EXCEPTION 'Invalid category name: Must be at least 1 character';
    END IF;

    -- 4. Atomic category insertion
    INSERT INTO public.categories (
        id,
        organization_id,
        name,
        description,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        p_organization_id,
        trim(p_name),
        NULLIF(trim(p_description), ''),
        clock_timestamp(),
        clock_timestamp()
    )
    RETURNING id INTO _category_id;

    RETURN jsonb_build_object(
        'success', true,
        'category_id', _category_id,
        'organization_id', p_organization_id,
        'name', trim(p_name)
    );
END;
$$;

-- Explicit execution grant strictly to authenticated users
GRANT EXECUTE ON FUNCTION public.create_category(uuid, text, text) TO authenticated;
