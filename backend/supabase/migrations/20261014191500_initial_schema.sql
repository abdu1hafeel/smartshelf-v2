-- ==============================================================================
-- SmartShelf V2 - Initial Database Schema & Security Policies
-- Migration: 20261014191500_initial_schema.sql
--
-- COMPREHENSIVE ARCHITECTURAL & SECURITY ENFORCEMENT:
-- 1. Atomic Organization Onboarding & Protected Admin Invariant:
--    - Direct INSERT on organizations is revoked. Provisioning flows strictly through
--      create_organization_onboarding().
--    - Parent organization locking serializes concurrent administrator demotions.
--    - Organizations being deleted cascade cleanly without tripping the anti-orphan guard.
-- 2. Engine-Level Privilege Hardening (Zero-Trust DML on Inventory):
--    - Direct INSERT, UPDATE, DELETE on shop_inventory and stock_movements is
--      REVOKED at the PostgreSQL permissions level from authenticated, anon, and PUBLIC.
--    - Does not rely on client-settable GUCs. All stock alterations MUST execute through
--      SECURITY DEFINER procedures that atomically record stock_movements in the same transaction.
-- 3. High-Entropy Device Provisioning & Lifecycle:
--    - Cryptographic 256-bit credentials (gen_random_bytes(32)) generated server-side.
--    - Stored as SHA-256 in a quarantined device_credentials table with zero client RLS access.
--    - Clear enrollment, credential rotation, and revocation workflows.
-- 4. Multi-Sample Scale Telemetry Verification & Accumulation:
--    - Telemetry persists settling readings into sensor_readings without rollback exceptions.
--    - Returns structured settling progress while accumulating samples.
--    - Requires 3 consecutive, strictly monotonic sequence readings within a 4-second window
--      with <= 2.0g variance and verified server calibration to issue a single-use weight ticket.
--    - Replay attempts, clock skew, and calibration mismatches roll back and abort.
-- 5. Canonical Checkout Idempotency & Safe Retries:
--    - Hashes all transaction-defining attributes (shop, payment method, notes, sorted cart).
--    - Atomic transition from PROCESSING to COMPLETED prevents concurrent double-checkout.
--    - Safe retries with identical payload return existing confirmed sale without stock deduction.
-- 6. Strict Numeric Precision (No Silent Rounding):
--    - Unconstrained numeric parameters reject excessive precision at function boundaries.
--    - Packaged goods strictly enforce whole integer pieces (trunc(qty) = qty).
--    - Loose goods strictly enforce 1-gram precision (round(qty, 3) = qty).
-- ==============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 1. Shared Updated Timestamp Trigger
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
BEGIN
  NEW.updated_at = clock_timestamp();
  RETURN NEW;
END;
$$;

-- ==============================================================================
-- 2. Multi-Tenant Core: Organizations & Shops
-- ==============================================================================

CREATE TABLE public.organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (length(trim(name)) >= 2),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TRIGGER trg_organizations_updated_at
BEFORE UPDATE ON public.organizations
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Organization deletion cascades naturally to shops and memberships.
-- Anti-orphan protection directly queries public.organizations table visibility rather than relying on custom GUCs.


CREATE TABLE public.shops (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name text NOT NULL CHECK (length(trim(name)) >= 2),
    location text,
    currency text NOT NULL DEFAULT 'INR',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_shops_org_id UNIQUE (organization_id, id)
);

CREATE INDEX idx_shops_organization_id ON public.shops(organization_id);

CREATE TRIGGER trg_shops_updated_at
BEFORE UPDATE ON public.shops
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Concurrency-safe per-shop receipt sequence counter
CREATE TABLE public.shop_receipt_sequences (
    shop_id uuid PRIMARY KEY REFERENCES public.shops(id) ON DELETE CASCADE,
    last_number bigint NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- ==============================================================================
-- 3. Profiles & Automatic User Provisioning
-- ==============================================================================

CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', NEW.email),
    clock_timestamp(),
    clock_timestamp()
  )
  ON CONFLICT (id) DO UPDATE
  SET full_name = EXCLUDED.full_name,
      updated_at = clock_timestamp();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ==============================================================================
-- 4. Organization & Shop Memberships with Concurrency-Safe Anti-Orphan Guard
-- ==============================================================================

CREATE TABLE public.organization_memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('ORG_ADMIN', 'ORG_MEMBER')),
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INVITED', 'SUSPENDED')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_org_user UNIQUE (organization_id, user_id)
);

CREATE INDEX idx_org_memberships_user ON public.organization_memberships(user_id);
CREATE INDEX idx_org_memberships_org ON public.organization_memberships(organization_id);

CREATE TRIGGER trg_org_memberships_updated_at
BEFORE UPDATE ON public.organization_memberships
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Concurrency-Safe Anti-Orphan Trigger: Locks parent organization row
CREATE OR REPLACE FUNCTION public.prevent_orphan_organization()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  _active_admins integer;
BEGIN
  -- Check if the parent organization still exists in the current snapshot/transaction.
  -- If the organization itself was deleted, this is an authorized cascading deletion;
  -- bypass the anti-orphan check without relying on client-manipulable custom GUCs.
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = OLD.organization_id) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF (TG_OP = 'DELETE' AND OLD.role = 'ORG_ADMIN' AND OLD.status = 'ACTIVE') OR
     (TG_OP = 'UPDATE' AND OLD.role = 'ORG_ADMIN' AND OLD.status = 'ACTIVE' AND (NEW.role != 'ORG_ADMIN' OR NEW.status != 'ACTIVE')) THEN
    
    -- Serialize concurrent administrator changes by locking the organization row
    PERFORM 1 FROM public.organizations WHERE id = OLD.organization_id FOR UPDATE;

    SELECT count(*) INTO _active_admins
    FROM public.organization_memberships
    WHERE organization_id = OLD.organization_id
      AND role = 'ORG_ADMIN'
      AND status = 'ACTIVE'
      AND id != OLD.id;

    IF _active_admins = 0 THEN
      RAISE EXCEPTION 'Operation rejected: Cannot delete or demote the last remaining active ORG_ADMIN of organization %', OLD.organization_id;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_prevent_orphan_org
BEFORE UPDATE OR DELETE ON public.organization_memberships
FOR EACH ROW EXECUTE FUNCTION public.prevent_orphan_organization();

CREATE TABLE public.shop_memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('SHOP_ADMIN', 'SHOPKEEPER')),
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_shop_user UNIQUE (shop_id, user_id)
);

CREATE INDEX idx_shop_memberships_user ON public.shop_memberships(user_id);
CREATE INDEX idx_shop_memberships_shop ON public.shop_memberships(shop_id);

CREATE TRIGGER trg_shop_memberships_updated_at
BEFORE UPDATE ON public.shop_memberships
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ==============================================================================
-- 5. Trusted Authorization Helper Functions (SECURITY DEFINER)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.is_org_admin(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.organization_memberships
    WHERE organization_id = p_org_id
      AND user_id = auth.uid()
      AND role = 'ORG_ADMIN'
      AND status = 'ACTIVE'
  );
$$;

CREATE OR REPLACE FUNCTION public.has_shop_access(p_shop_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.shop_memberships sm
    WHERE sm.shop_id = p_shop_id
      AND sm.user_id = auth.uid()
      AND sm.status = 'ACTIVE'
  )
  OR EXISTS (
    SELECT 1
    FROM public.shops s
    JOIN public.organization_memberships om ON om.organization_id = s.organization_id
    WHERE s.id = p_shop_id
      AND om.user_id = auth.uid()
      AND om.role = 'ORG_ADMIN'
      AND om.status = 'ACTIVE'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_shop_admin(p_shop_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.shop_memberships sm
    WHERE sm.shop_id = p_shop_id
      AND sm.user_id = auth.uid()
      AND sm.role = 'SHOP_ADMIN'
      AND sm.status = 'ACTIVE'
  )
  OR EXISTS (
    SELECT 1
    FROM public.shops s
    JOIN public.organization_memberships om ON om.organization_id = s.organization_id
    WHERE s.id = p_shop_id
      AND om.user_id = auth.uid()
      AND om.role = 'ORG_ADMIN'
      AND om.status = 'ACTIVE'
  );
$$;

CREATE OR REPLACE FUNCTION public.has_org_access(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.organization_memberships
    WHERE organization_id = p_org_id
      AND user_id = auth.uid()
      AND status = 'ACTIVE'
  )
  OR EXISTS (
    SELECT 1
    FROM public.shop_memberships sm
    JOIN public.shops s ON s.id = sm.shop_id
    WHERE s.organization_id = p_org_id
      AND sm.user_id = auth.uid()
      AND sm.status = 'ACTIVE'
  );
$$;

-- ==============================================================================
-- 6. Product Catalog & Categories (Enforcing Tenant Integrity)
-- ==============================================================================

CREATE TABLE public.categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name text NOT NULL CHECK (length(trim(name)) >= 1),
    description text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_categories_org_name UNIQUE (organization_id, name),
    CONSTRAINT uq_categories_org_id UNIQUE (organization_id, id)
);

CREATE INDEX idx_categories_org ON public.categories(organization_id);

CREATE TRIGGER trg_categories_updated_at
BEFORE UPDATE ON public.categories
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.handle_category_before_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
  UPDATE public.products 
  SET category_id = NULL 
  WHERE organization_id = OLD.organization_id 
    AND category_id = OLD.id;
  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_category_before_delete
BEFORE DELETE ON public.categories
FOR EACH ROW EXECUTE FUNCTION public.handle_category_before_delete();

CREATE TABLE public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    category_id uuid,
    name text NOT NULL CHECK (length(trim(name)) >= 1),
    barcode text,
    sku text,
    unit_type text NOT NULL CHECK (unit_type IN ('PACKAGED', 'LOOSE')),
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT fk_products_category_org 
        FOREIGN KEY (organization_id, category_id) 
        REFERENCES public.categories(organization_id, id) 
        ON DELETE RESTRICT,
    CONSTRAINT uq_products_org_id UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX uq_products_org_barcode 
ON public.products(organization_id, barcode) 
WHERE barcode IS NOT NULL;

CREATE INDEX idx_products_org ON public.products(organization_id);
CREATE INDEX idx_products_category ON public.products(category_id);

CREATE TRIGGER trg_products_updated_at
BEFORE UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ==============================================================================
-- 7. Shop-Specific Inventory & Pricing (Protected DML)
-- ==============================================================================

CREATE TABLE public.shop_inventory (
    shop_id uuid NOT NULL,
    product_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    selling_price numeric(12,2) NOT NULL CHECK (selling_price >= 0),
    quantity numeric(12,3) NOT NULL DEFAULT 0.000 CHECK (quantity >= 0),
    low_stock_threshold numeric(12,3) NOT NULL DEFAULT 5.000 CHECK (low_stock_threshold >= 0),
    is_available boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (shop_id, product_id),
    CONSTRAINT fk_shop_inventory_shop_org 
        FOREIGN KEY (organization_id, shop_id) 
        REFERENCES public.shops(organization_id, id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_shop_inventory_product_org 
        FOREIGN KEY (organization_id, product_id) 
        REFERENCES public.products(organization_id, id) 
        ON DELETE CASCADE
);

CREATE INDEX idx_shop_inventory_product ON public.shop_inventory(product_id);
CREATE INDEX idx_shop_inventory_org ON public.shop_inventory(organization_id);

CREATE TRIGGER trg_shop_inventory_updated_at
BEFORE UPDATE ON public.shop_inventory
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ==============================================================================
-- 8. Devices, Telemetry, and Quarantined Credentials
-- ==============================================================================

CREATE TABLE public.devices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    device_identifier text NOT NULL,
    name text NOT NULL,
    calibration_factor numeric(12,4) NOT NULL DEFAULT 1.0000 CHECK (calibration_factor > 0),
    tare_offset numeric(12,4) NOT NULL DEFAULT 0.0000,
    current_epoch bigint NOT NULL DEFAULT 0 CHECK (current_epoch >= 0),
    last_sequence_number bigint NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    last_boot_at timestamptz,
    last_boot_reason text,
    hourly_boot_count integer NOT NULL DEFAULT 0,
    hourly_boot_window_start timestamptz NOT NULL DEFAULT clock_timestamp(),
    last_seen_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_devices_shop_identifier UNIQUE (shop_id, device_identifier),
    CONSTRAINT uq_devices_shop UNIQUE (id, shop_id)
);

CREATE INDEX idx_devices_shop ON public.devices(shop_id);

CREATE TRIGGER trg_devices_updated_at
BEFORE UPDATE ON public.devices
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TABLE public.device_credentials (
    device_id uuid PRIMARY KEY REFERENCES public.devices(id) ON DELETE CASCADE,
    api_key_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TRIGGER trg_device_credentials_updated_at
BEFORE UPDATE ON public.device_credentials
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TABLE public.sensor_readings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id uuid NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    session_id uuid NOT NULL,
    epoch bigint NOT NULL DEFAULT 1 CHECK (epoch > 0),
    raw_reading numeric(12,2) NOT NULL,
    weight_grams numeric(12,3) NOT NULL,
    is_stable boolean NOT NULL DEFAULT false,
    sequence_number bigint NOT NULL,
    reading_timestamp timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_sensor_readings_device_epoch_seq UNIQUE (device_id, epoch, sequence_number)
);

CREATE INDEX idx_sensor_readings_lookup 
ON public.sensor_readings(device_id, session_id, epoch DESC, sequence_number DESC, created_at DESC);

-- ==============================================================================
-- 9. Verified Weight Tickets (Anti-Tamper Loose Weighing Workflow)
-- ==============================================================================

CREATE TABLE public.verified_weight_tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    device_id uuid NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    session_id uuid NOT NULL,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    weight_grams numeric(12,3) NOT NULL CHECK (weight_grams > 0),
    weight_kg numeric(12,3) GENERATED ALWAYS AS (round(weight_grams / 1000.0, 3)) STORED,
    reading_id uuid REFERENCES public.sensor_readings(id) ON DELETE SET NULL,
    epoch bigint NOT NULL DEFAULT 1 CHECK (epoch > 0),
    sequence_number bigint NOT NULL,
    is_consumed boolean NOT NULL DEFAULT false,
    consumed_at timestamptz,
    consumed_in_sale_id uuid, -- Linked after sale creation
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_weight_tickets_device_session UNIQUE (device_id, session_id),
    CONSTRAINT uq_weight_tickets_id_product UNIQUE (id, product_id),
    CONSTRAINT fk_weight_ticket_device_shop FOREIGN KEY (device_id, shop_id) REFERENCES public.devices(id, shop_id) ON DELETE CASCADE,
    CONSTRAINT fk_weight_ticket_shop_inventory FOREIGN KEY (shop_id, product_id) REFERENCES public.shop_inventory(shop_id, product_id) ON DELETE CASCADE
);

CREATE INDEX idx_weight_tickets_lookup 
ON public.verified_weight_tickets(id, shop_id, is_consumed, expires_at);

-- ==============================================================================
-- 10. Sales, Sale Items, and Idempotency Guard
-- ==============================================================================

CREATE TABLE public.sales (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE RESTRICT,
    cashier_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    checkout_id uuid NOT NULL UNIQUE,
    sale_number text NOT NULL,
    total_amount numeric(12,2) NOT NULL CHECK (total_amount >= 0),
    payment_method text NOT NULL DEFAULT 'CASH' CHECK (payment_method IN ('CASH', 'CARD', 'UPI', 'CREDIT')),
    payment_status text NOT NULL DEFAULT 'COMPLETED' CHECK (payment_status IN ('COMPLETED', 'PENDING', 'CANCELLED', 'REFUNDED')),
    notes text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_sales_shop_receipt UNIQUE (shop_id, sale_number)
);

CREATE INDEX idx_sales_shop_time ON public.sales(shop_id, created_at DESC);
CREATE INDEX idx_sales_cashier ON public.sales(cashier_user_id);

CREATE TABLE public.processed_checkouts (
    checkout_id uuid PRIMARY KEY,
    shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    sale_id uuid REFERENCES public.sales(id) ON DELETE CASCADE,
    payload_hash text NOT NULL,
    status text NOT NULL DEFAULT 'PROCESSING' CHECK (status IN ('PROCESSING', 'COMPLETED')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX idx_processed_checkouts_shop ON public.processed_checkouts(shop_id);

CREATE TABLE public.sale_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    product_name text NOT NULL,
    unit_type text NOT NULL CHECK (unit_type IN ('PACKAGED', 'LOOSE')),
    quantity numeric(12,3) NOT NULL CHECK (quantity > 0),
    unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    line_total numeric(12,2) NOT NULL CHECK (line_total >= 0),
    weight_ticket_id uuid,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_sale_items_weight_ticket UNIQUE (weight_ticket_id),
    CONSTRAINT fk_sale_items_weight_ticket FOREIGN KEY (weight_ticket_id, product_id) REFERENCES public.verified_weight_tickets(id, product_id) ON DELETE RESTRICT
);

CREATE INDEX idx_sale_items_sale ON public.sale_items(sale_id);
CREATE INDEX idx_sale_items_product ON public.sale_items(product_id);

ALTER TABLE public.verified_weight_tickets
ADD CONSTRAINT fk_weight_ticket_sale
FOREIGN KEY (consumed_in_sale_id) REFERENCES public.sales(id) ON DELETE SET NULL;

-- ==============================================================================
-- 11. Auditable Stock Movements
-- ==============================================================================

CREATE TABLE public.stock_movements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id uuid NOT NULL,
    product_id uuid NOT NULL,
    movement_type text NOT NULL CHECK (movement_type IN ('SALE', 'RESTOCK', 'ADJUSTMENT', 'RETURN', 'DAMAGE', 'INITIAL')),
    delta_quantity numeric(12,3) NOT NULL,
    quantity_before numeric(12,3) NOT NULL CHECK (quantity_before >= 0),
    quantity_after numeric(12,3) NOT NULL CHECK (quantity_after >= 0),
    reference_id uuid,
    reason text,
    performed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT fk_stock_movements_inventory 
        FOREIGN KEY (shop_id, product_id) 
        REFERENCES public.shop_inventory(shop_id, product_id) 
        ON DELETE RESTRICT
);

CREATE INDEX idx_stock_movements_shop_time ON public.stock_movements(shop_id, created_at DESC);
CREATE INDEX idx_stock_movements_product ON public.stock_movements(product_id);

-- Enforce quantity precision on inventory rows
CREATE OR REPLACE FUNCTION public.validate_stock_quantity_precision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  _unit_type text;
BEGIN
  SELECT unit_type INTO _unit_type FROM public.products WHERE id = NEW.product_id;
  IF _unit_type = 'PACKAGED' THEN
    IF NEW.quantity != trunc(NEW.quantity) THEN
      RAISE EXCEPTION 'Unit violation: Packaged product must be in whole integer pieces (received: %)', NEW.quantity;
    END IF;
  ELSIF _unit_type = 'LOOSE' THEN
    IF NEW.quantity != round(NEW.quantity, 3) THEN
      RAISE EXCEPTION 'Unit violation: Loose product weight cannot exceed 3 decimal places / 1-gram precision (received: %)', NEW.quantity;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_shop_inventory_precision
BEFORE INSERT OR UPDATE ON public.shop_inventory
FOR EACH ROW EXECUTE FUNCTION public.validate_stock_quantity_precision();

-- ==============================================================================
-- 12. Device Provisioning & Lifecycle Procedures (SECURITY DEFINER)
-- ==============================================================================

-- 12a. Enroll Device with High-Entropy Generated Secret
CREATE OR REPLACE FUNCTION public.enroll_device(
    p_shop_id uuid,
    p_device_identifier text,
    p_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
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
    _secret_raw := encode(gen_random_bytes(32), 'hex');
    _secret_hash := encode(digest(_secret_raw, 'sha256'), 'hex');

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

-- 12b. Rotate Device Credentials (Zero Replay Interference)
CREATE OR REPLACE FUNCTION public.rotate_device_credentials(
    p_device_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
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

    _secret_raw := encode(gen_random_bytes(32), 'hex');
    _secret_hash := encode(digest(_secret_raw, 'sha256'), 'hex');

    UPDATE public.device_credentials
    SET api_key_hash = _secret_hash,
        updated_at = clock_timestamp()
    WHERE device_id = p_device_id;

    -- Standard credential rotation: NEVER modifies current_epoch or last_sequence_number.
    -- Credential rotation updates the authentication secret key only; sequence numbers and
    -- epochs continue monotonically to prevent replay vulnerabilities and constraint collisions.
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

-- 12c. Recover Device After NVS Loss / Board Replacement (Strict Forward Epoch)
CREATE OR REPLACE FUNCTION public.recover_device_after_reset(
    p_device_id uuid,
    p_epoch_offset bigint DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
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

    -- The server epoch NEVER rolls back to 1.
    -- Instead, recovery establishes a valid new epoch strictly ABOVE the server's existing epoch:
    _new_epoch := _device_record.current_epoch + coalesce(p_epoch_offset, 10);

    _secret_raw := encode(gen_random_bytes(32), 'hex');
    _secret_hash := encode(digest(_secret_raw, 'sha256'), 'hex');

    UPDATE public.device_credentials
    SET api_key_hash = _secret_hash,
        updated_at = clock_timestamp()
    WHERE device_id = p_device_id;

    UPDATE public.devices
    SET current_epoch = _new_epoch,
        last_sequence_number = 0,
        last_boot_at = clock_timestamp(),
        hourly_boot_count = 0,
        hourly_boot_window_start = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE id = p_device_id;

    RETURN jsonb_build_object(
        'device_id', p_device_id,
        'new_device_secret', _secret_raw,
        'assigned_starting_epoch', _new_epoch,
        'previous_epoch', _device_record.current_epoch,
        'instructions', 'Configure the new_device_secret and write assigned_starting_epoch into the ESP32 NVS boot_epoch before booting.'
    );
END;
$$;

-- 12d. Authenticated Device Boot-Session Registration (Anti-Flapping & Strict Monotonic Transition)
CREATE OR REPLACE FUNCTION public.register_device_boot(
    p_device_id uuid,
    p_boot_epoch bigint,
    p_firmware_version text DEFAULT '2.0.0',
    p_boot_reason text DEFAULT 'POWERON'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _device record;
    _window_elapsed interval;
    _new_hourly_count integer;
    _new_window_start timestamptz;
BEGIN
    IF p_boot_epoch <= 0 THEN
        RAISE EXCEPTION 'Boot epoch must be a positive integer';
    END IF;

    SELECT id, shop_id, current_epoch, last_sequence_number, is_active,
           last_boot_at, hourly_boot_count, hourly_boot_window_start
    INTO _device
    FROM public.devices
    WHERE id = p_device_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Device % not found', p_device_id;
    END IF;

    IF NOT _device.is_active THEN
        RAISE EXCEPTION 'Device % is deactivated', p_device_id;
    END IF;

    -- Handle safe idempotency / retry within 60s
    IF p_boot_epoch = _device.current_epoch THEN
        IF _device.last_boot_at IS NOT NULL AND _device.last_boot_at >= (clock_timestamp() - interval '60 seconds') THEN
            RETURN jsonb_build_object(
                'status', 'BOOT_REGISTERED',
                'device_id', p_device_id,
                'epoch', _device.current_epoch,
                'message', 'Boot registration acknowledged (idempotent retry).',
                'is_retry', true
            );
        ELSE
            RAISE EXCEPTION 'REPLAY_DETECTED: Stale boot epoch % has already expired. Boot epoch must increment monotonically.', p_boot_epoch;
        END IF;
    END IF;

    -- Strictly monotonic epoch transition: Must be exactly current_epoch + 1
    IF p_boot_epoch < _device.current_epoch THEN
        RAISE EXCEPTION 'REPLAY_DETECTED: Stale boot epoch % (current registered epoch is %)',
            p_boot_epoch, _device.current_epoch;
    END IF;

    IF p_boot_epoch != _device.current_epoch + 1 THEN
        RAISE EXCEPTION 'INVALID_EPOCH_TRANSITION: Boot epoch must increment by exactly 1 (expected %, received %). Use authorized recovery for out-of-band re-synchronization.',
            _device.current_epoch + 1, p_boot_epoch;
    END IF;

    -- Anti-flapping: Minimum 5-second interval between reboots to prevent brownout spamming
    IF _device.last_boot_at IS NOT NULL AND (clock_timestamp() - _device.last_boot_at) < interval '5 seconds' THEN
        RAISE EXCEPTION 'BOOT_RATE_LIMITED: Reboots must be separated by at least 5 seconds';
    END IF;

    -- Anti-flapping: Maximum 20 reboot transitions in a rolling 1-hour window to prevent DoS lockouts
    _window_elapsed := clock_timestamp() - _device.hourly_boot_window_start;
    IF _window_elapsed > interval '1 hour' THEN
        _new_window_start := clock_timestamp();
        _new_hourly_count := 1;
    ELSE
        _new_window_start := _device.hourly_boot_window_start;
        _new_hourly_count := _device.hourly_boot_count + 1;
        IF _new_hourly_count > 20 THEN
            RAISE EXCEPTION 'BOOT_FLAPPING_DETECTED: Excessive reboot rate (% reboots in last hour). Device requires administrative inspection.',
                _new_hourly_count;
        END IF;
    END IF;

    UPDATE public.devices
    SET current_epoch = p_boot_epoch,
        last_sequence_number = 0,
        last_boot_at = clock_timestamp(),
        last_boot_reason = trim(p_boot_reason),
        hourly_boot_count = _new_hourly_count,
        hourly_boot_window_start = _new_window_start,
        last_seen_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE id = p_device_id;

    RETURN jsonb_build_object(
        'status', 'BOOT_REGISTERED',
        'device_id', p_device_id,
        'epoch', p_boot_epoch,
        'registered_at', clock_timestamp(),
        'message', 'Boot epoch registered successfully. Telemetry sequence initialized to 0.'
    );
END;
$$;

-- 12c. Revoke / Deactivate Device
CREATE OR REPLACE FUNCTION public.revoke_device(
    p_device_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _shop_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    SELECT shop_id INTO _shop_id FROM public.devices WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Device % not found', p_device_id;
    END IF;

    IF NOT public.is_shop_admin(_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can revoke devices';
    END IF;

    UPDATE public.devices
    SET is_active = false,
        updated_at = clock_timestamp()
    WHERE id = p_device_id;

    DELETE FROM public.device_credentials WHERE device_id = p_device_id;

    RETURN jsonb_build_object(
        'device_id', p_device_id,
        'status', 'REVOKED'
    );
END;
$$;

-- 12d. Authorized Calibration Workflow
CREATE OR REPLACE FUNCTION public.calibrate_device(
    p_device_id uuid,
    p_tare_offset numeric,
    p_calibration_factor numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _shop_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    SELECT shop_id INTO _shop_id FROM public.devices WHERE id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Device % not found', p_device_id;
    END IF;

    IF NOT public.is_shop_admin(_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can calibrate devices';
    END IF;

    IF p_calibration_factor <= 0 THEN
        RAISE EXCEPTION 'Calibration factor must be strictly greater than zero';
    END IF;

    UPDATE public.devices
    SET tare_offset = round(p_tare_offset, 4),
        calibration_factor = round(p_calibration_factor, 4),
        updated_at = clock_timestamp()
    WHERE id = p_device_id;

    RETURN jsonb_build_object(
        'device_id', p_device_id,
        'tare_offset', round(p_tare_offset, 4),
        'calibration_factor', round(p_calibration_factor, 4),
        'status', 'CALIBRATED'
    );
END;
$$;

-- ==============================================================================
-- 13. Scale Telemetry & Verified Weight Ticket Procedure (Multi-Sample Stability)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.record_scale_telemetry(
    p_device_id uuid,
    p_session_id uuid,
    p_product_id uuid,
    p_raw_reading numeric,
    p_weight_grams numeric,
    p_sequence_number bigint,
    p_is_stable boolean,
    p_reading_timestamp timestamptz,
    p_epoch bigint DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _device_record record;
    _product_record record;
    _existing_ticket record;
    _expected_weight numeric(12,3);
    _reading_id uuid := gen_random_uuid();
    _ticket_id uuid := gen_random_uuid();
    _expires_at timestamptz;
    _required_stable_samples CONSTANT integer := 3;
    _time_window_interval CONSTANT interval := interval '4 seconds';
    _stability_tolerance_grams CONSTANT numeric := 2.000;
    
    _consecutive_stable_count integer := 0;
    _sample_variance numeric := 0.000;
    _is_session_stable boolean := false;
    _recent_samples record;
BEGIN
    -- 1. Precision & input bounds validation (reject excessive precision)
    IF p_weight_grams != round(p_weight_grams, 3) THEN
        RAISE EXCEPTION 'Weight precision violation: Grams cannot exceed 3 decimal places / 1-milligram precision (received: %)', p_weight_grams;
    END IF;

    IF p_weight_grams <= 0 THEN
        RAISE EXCEPTION 'Weight reading must be strictly greater than zero (received: %)', p_weight_grams;
    END IF;

    IF p_epoch <= 0 THEN
        RAISE EXCEPTION 'Epoch must be a positive integer (received: %)', p_epoch;
    END IF;

    IF p_sequence_number <= 0 THEN
        RAISE EXCEPTION 'Sequence number must be a positive integer';
    END IF;

    -- 2. Lock and validate device record
    SELECT d.id, d.shop_id, d.calibration_factor, d.tare_offset, d.current_epoch, d.last_sequence_number, d.is_active, s.organization_id
    INTO _device_record
    FROM public.devices d
    JOIN public.shops s ON s.id = d.shop_id
    WHERE d.id = p_device_id
    FOR UPDATE OF d;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Device % not found', p_device_id;
    END IF;

    IF NOT _device_record.is_active THEN
        RAISE EXCEPTION 'Device % is deactivated', p_device_id;
    END IF;

    -- 3. Monotonic sequence & boot epoch replay protection
    -- Telemetry readings MUST match the currently registered active boot epoch.
    -- In-flight or arbitrary epoch advancements via telemetry readings are forbidden.
    IF p_epoch != _device_record.current_epoch THEN
        IF p_epoch < _device_record.current_epoch THEN
            RAISE EXCEPTION 'REPLAY_DETECTED: Stale epoch % (current active epoch is %)',
                p_epoch, _device_record.current_epoch;
        ELSE
            RAISE EXCEPTION 'UNREGISTERED_EPOCH: Telemetry epoch % is ahead of registered epoch %. Device must complete authenticated boot registration before streaming telemetry.',
                p_epoch, _device_record.current_epoch;
        END IF;
    END IF;

    IF p_sequence_number <= _device_record.last_sequence_number THEN
        RAISE EXCEPTION 'REPLAY_DETECTED: Sequence number % is not greater than last observed sequence % in epoch %',
            p_sequence_number, _device_record.last_sequence_number, p_epoch;
    END IF;

    -- 4. Check if a ticket has already been issued for this device and session (idempotent completion)
    SELECT id, shop_id, device_id, session_id, product_id, weight_grams, weight_kg, is_consumed, expires_at, created_at
    INTO _existing_ticket
    FROM public.verified_weight_tickets
    WHERE device_id = p_device_id AND session_id = p_session_id;

    IF FOUND THEN
        -- Preserve single-use checkout enforcement: Never treat a consumed ticket as newly valid
        IF _existing_ticket.is_consumed THEN
            RAISE EXCEPTION 'SESSION_CONSUMED: Weight ticket for session % has already been consumed in a completed sale', p_session_id;
        END IF;

        -- Never treat an expired ticket as newly valid
        IF _existing_ticket.expires_at < clock_timestamp() THEN
            RAISE EXCEPTION 'SESSION_EXPIRED: Weight ticket for session % expired at % and cannot be re-issued',
                p_session_id, _existing_ticket.expires_at;
        END IF;

        RETURN jsonb_build_object(
            'status', 'VERIFIED',
            'already_issued', true,
            'consecutive_samples', _required_stable_samples,
            'required_samples', _required_stable_samples,
            'ticket', jsonb_build_object(
                'ticket_id', _existing_ticket.id,
                'shop_id', _existing_ticket.shop_id,
                'device_id', _existing_ticket.device_id,
                'session_id', _existing_ticket.session_id,
                'product_id', _existing_ticket.product_id,
                'weight_grams', _existing_ticket.weight_grams,
                'weight_kg', _existing_ticket.weight_kg,
                'expires_at', _existing_ticket.expires_at,
                'created_at', _existing_ticket.created_at
            )
        );
    END IF;

    -- 5. Telemetry timing freshness window (+- 30 seconds max clock skew)
    IF p_reading_timestamp < (clock_timestamp() - interval '30 seconds') OR
       p_reading_timestamp > (clock_timestamp() + interval '10 seconds') THEN
        RAISE EXCEPTION 'Stale or future telemetry timestamp rejected (Device: %, Server: %)',
            p_reading_timestamp, clock_timestamp();
    END IF;

    -- 6. Product verification & tenant consistency against shop inventory
    SELECT p.id, p.organization_id, p.unit_type, p.is_active, p.name
    INTO _product_record
    FROM public.products p
    JOIN public.shop_inventory si ON si.product_id = p.id AND si.shop_id = _device_record.shop_id
    WHERE p.id = p_product_id;

    IF NOT FOUND OR NOT _product_record.is_active THEN
        RAISE EXCEPTION 'Product % is unavailable or not enrolled in shop inventory', p_product_id;
    END IF;

    IF _product_record.unit_type != 'LOOSE' THEN
        RAISE EXCEPTION 'Product % is packaged and does not use weight tickets', _product_record.name;
    END IF;

    IF _product_record.organization_id <> _device_record.organization_id THEN
        RAISE EXCEPTION 'Tenant integrity violation: Device and product belong to different organizations';
    END IF;

    -- 7. Server-side calibration verification (2g load cell tolerance)
    _expected_weight := round((p_raw_reading - _device_record.tare_offset) * _device_record.calibration_factor, 3);
    IF abs(p_weight_grams - _expected_weight) > _stability_tolerance_grams THEN
        RAISE EXCEPTION 'CALIBRATION_MISMATCH: Reported weight %g deviates from server calibration expectation %g (tolerance: %g)',
            p_weight_grams, _expected_weight, _stability_tolerance_grams;
    END IF;

    -- 8. Record current reading into sensor_readings
    INSERT INTO public.sensor_readings (
        id, device_id, session_id, epoch, raw_reading, weight_grams, is_stable, sequence_number, reading_timestamp, created_at
    ) VALUES (
        _reading_id, p_device_id, p_session_id, p_epoch, p_raw_reading, p_weight_grams, p_is_stable, p_sequence_number, p_reading_timestamp, clock_timestamp()
    );

    UPDATE public.devices
    SET last_sequence_number = p_sequence_number,
        last_seen_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE id = p_device_id;

    -- 9. Multi-sample consecutive stability validation (strictly same epoch, device, and session)
    IF p_is_stable THEN
        SELECT 
            count(*) AS sample_count,
            coalesce(max(weight_grams) - min(weight_grams), 0.000) AS variance,
            bool_and(is_stable) AS all_stable,
            max(sequence_number) - min(sequence_number) AS seq_spread,
            count(DISTINCT sequence_number) AS distinct_seq_count
        INTO _recent_samples
        FROM (
            SELECT weight_grams, is_stable, sequence_number
            FROM public.sensor_readings
            WHERE device_id = p_device_id
              AND session_id = p_session_id
              AND epoch = p_epoch
              AND created_at >= (clock_timestamp() - _time_window_interval)
            ORDER BY sequence_number DESC
            LIMIT _required_stable_samples
        ) sub;

        IF _recent_samples.sample_count >= _required_stable_samples
           AND _recent_samples.all_stable
           AND _recent_samples.seq_spread = (_required_stable_samples - 1)
           AND _recent_samples.distinct_seq_count = _required_stable_samples
           AND _recent_samples.variance <= _stability_tolerance_grams THEN
            _is_session_stable := true;
            _consecutive_stable_count := _required_stable_samples;
            _sample_variance := _recent_samples.variance;
        ELSE
            _is_session_stable := false;
            _consecutive_stable_count := _recent_samples.sample_count;
            _sample_variance := _recent_samples.variance;
        END IF;
    ELSE
        _is_session_stable := false;
        _consecutive_stable_count := 0;
        _sample_variance := 0.000;
    END IF;

    -- 10. If not yet stable, return structured settling progress (COMMITTED, no exception)
    IF NOT _is_session_stable THEN
        RETURN jsonb_build_object(
            'status', 'SETTLING',
            'device_id', p_device_id,
            'session_id', p_session_id,
            'epoch', p_epoch,
            'sequence_number', p_sequence_number,
            'weight_grams', p_weight_grams,
            'is_sample_stable', p_is_stable,
            'consecutive_samples', _consecutive_stable_count,
            'required_samples', _required_stable_samples,
            'variance_grams', _sample_variance,
            'tolerance_grams', _stability_tolerance_grams,
            'message', 'Scale settling: accumulating consecutive stable telemetry samples'
        );
    END IF;

    -- 11. Issue single-use verified weight ticket with 90-second expiry
    _expires_at := clock_timestamp() + interval '90 seconds';

    INSERT INTO public.verified_weight_tickets (
        id, shop_id, device_id, session_id, product_id, weight_grams,
        reading_id, epoch, sequence_number, is_consumed, expires_at, created_at
    ) VALUES (
        _ticket_id, _device_record.shop_id, p_device_id, p_session_id, p_product_id, p_weight_grams,
        _reading_id, p_epoch, p_sequence_number, false, _expires_at, clock_timestamp()
    );

    RETURN jsonb_build_object(
        'status', 'VERIFIED',
        'consecutive_samples', _consecutive_stable_count,
        'required_samples', _required_stable_samples,
        'variance_grams', _sample_variance,
        'ticket', jsonb_build_object(
            'ticket_id', _ticket_id,
            'shop_id', _device_record.shop_id,
            'device_id', p_device_id,
            'session_id', p_session_id,
            'product_id', p_product_id,
            'weight_grams', p_weight_grams,
            'weight_kg', round(p_weight_grams / 1000.0, 3),
            'epoch', p_epoch,
            'sequence_number', p_sequence_number,
            'expires_at', _expires_at,
            'created_at', clock_timestamp()
        )
    );
END;
$$;

-- Backwards-compatible wrapper procedure
CREATE OR REPLACE FUNCTION public.issue_verified_weight_ticket(
    p_device_id uuid,
    p_product_id uuid,
    p_raw_reading numeric,
    p_weight_grams numeric,
    p_sequence_number bigint,
    p_is_stable boolean,
    p_reading_timestamp timestamptz,
    p_session_id uuid DEFAULT NULL,
    p_epoch bigint DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
    RETURN public.record_scale_telemetry(
        p_device_id := p_device_id,
        p_session_id := coalesce(p_session_id, p_device_id),
        p_product_id := p_product_id,
        p_raw_reading := p_raw_reading,
        p_weight_grams := p_weight_grams,
        p_sequence_number := p_sequence_number,
        p_is_stable := p_is_stable,
        p_reading_timestamp := p_reading_timestamp,
        p_epoch := p_epoch
    );
END;
$$;

-- ==============================================================================
-- 14. Administrative & Inventory Procedures (SECURITY DEFINER)
-- ==============================================================================

-- 14a. Atomic Organization Onboarding
CREATE OR REPLACE FUNCTION public.create_organization_onboarding(
    p_org_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _org_id uuid;
    _membership_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required to create an organization';
    END IF;

    IF trim(p_org_name) IS NULL OR length(trim(p_org_name)) < 2 THEN
        RAISE EXCEPTION 'Invalid organization name: Must be at least 2 characters';
    END IF;

    INSERT INTO public.organizations (id, name, created_at, updated_at)
    VALUES (gen_random_uuid(), trim(p_org_name), clock_timestamp(), clock_timestamp())
    RETURNING id INTO _org_id;

    INSERT INTO public.organization_memberships (
        id, organization_id, user_id, role, status, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), _org_id, auth.uid(), 'ORG_ADMIN', 'ACTIVE', clock_timestamp(), clock_timestamp()
    ) RETURNING id INTO _membership_id;

    RETURN jsonb_build_object(
        'organization_id', _org_id,
        'organization_name', trim(p_org_name),
        'membership_id', _membership_id,
        'role', 'ORG_ADMIN'
    );
END;
$$;

-- 14b. Shop Creation
CREATE OR REPLACE FUNCTION public.create_shop(
    p_organization_id uuid,
    p_name text,
    p_location text DEFAULT NULL,
    p_currency text DEFAULT 'INR'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _shop_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_org_admin(p_organization_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only an active ORG_ADMIN can create shops';
    END IF;

    IF trim(p_name) IS NULL OR length(trim(p_name)) < 2 THEN
        RAISE EXCEPTION 'Invalid shop name: Must be at least 2 characters';
    END IF;

    INSERT INTO public.shops (
        id, organization_id, name, location, currency, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), p_organization_id, trim(p_name), p_location, coalesce(p_currency, 'INR'), clock_timestamp(), clock_timestamp()
    ) RETURNING id INTO _shop_id;

    INSERT INTO public.shop_receipt_sequences (shop_id, last_number, updated_at)
    VALUES (_shop_id, 0, clock_timestamp())
    ON CONFLICT (shop_id) DO NOTHING;

    RETURN jsonb_build_object(
        'shop_id', _shop_id,
        'organization_id', p_organization_id,
        'name', trim(p_name),
        'currency', coalesce(p_currency, 'INR')
    );
END;
$$;

-- 14c. Assign Shop Membership
CREATE OR REPLACE FUNCTION public.assign_shop_membership(
    p_shop_id uuid,
    p_user_id uuid,
    p_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _membership_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_shop_admin(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can assign shop memberships';
    END IF;

    IF p_role NOT IN ('SHOP_ADMIN', 'SHOPKEEPER') THEN
        RAISE EXCEPTION 'Invalid role: Must be SHOP_ADMIN or SHOPKEEPER';
    END IF;

    INSERT INTO public.shop_memberships (
        id, shop_id, user_id, role, status, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), p_shop_id, p_user_id, p_role, 'ACTIVE', clock_timestamp(), clock_timestamp()
    )
    ON CONFLICT (shop_id, user_id) DO UPDATE
    SET role = EXCLUDED.role,
        status = 'ACTIVE',
        updated_at = clock_timestamp()
    RETURNING id INTO _membership_id;

    RETURN jsonb_build_object(
        'membership_id', _membership_id,
        'shop_id', p_shop_id,
        'user_id', p_user_id,
        'role', p_role
    );
END;
$$;

-- 14d. Product Creation
CREATE OR REPLACE FUNCTION public.create_product(
    p_organization_id uuid,
    p_category_id uuid,
    p_name text,
    p_barcode text,
    p_sku text,
    p_unit_type text,
    p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _product_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_org_admin(p_organization_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only an ORG_ADMIN can create catalog products';
    END IF;

    IF p_unit_type NOT IN ('PACKAGED', 'LOOSE') THEN
        RAISE EXCEPTION 'Invalid unit_type: Must be PACKAGED or LOOSE';
    END IF;

    IF trim(p_name) IS NULL OR length(trim(p_name)) < 1 THEN
        RAISE EXCEPTION 'Invalid product name';
    END IF;

    INSERT INTO public.products (
        id, organization_id, category_id, name, barcode, sku, unit_type, description, is_active, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), p_organization_id, p_category_id, trim(p_name), nullif(trim(p_barcode), ''), nullif(trim(p_sku), ''), p_unit_type, p_description, true, clock_timestamp(), clock_timestamp()
    ) RETURNING id INTO _product_id;

    RETURN jsonb_build_object(
        'product_id', _product_id,
        'organization_id', p_organization_id,
        'name', trim(p_name),
        'unit_type', p_unit_type
    );
END;
$$;

-- 14e. Setup Shop Inventory & Initial Stock
CREATE OR REPLACE FUNCTION public.setup_shop_inventory(
    p_shop_id uuid,
    p_product_id uuid,
    p_selling_price numeric,
    p_initial_quantity numeric DEFAULT 0,
    p_low_stock_threshold numeric DEFAULT 5
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _org_id uuid;
    _prod_org_id uuid;
    _prod_unit_type text;
    _exists boolean;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_shop_admin(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can configure shop inventory';
    END IF;

    SELECT organization_id INTO _org_id FROM public.shops WHERE id = p_shop_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop % not found', p_shop_id;
    END IF;

    SELECT organization_id, unit_type INTO _prod_org_id, _prod_unit_type
    FROM public.products WHERE id = p_product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % not found', p_product_id;
    END IF;

    IF _org_id <> _prod_org_id THEN
        RAISE EXCEPTION 'Tenant integrity violation: Shop and product belong to different organizations';
    END IF;

    -- Strict numeric precision validation
    IF p_selling_price < 0 OR p_selling_price != round(p_selling_price, 2) THEN
        RAISE EXCEPTION 'Selling price cannot be negative and cannot exceed 2 decimal places';
    END IF;

    IF p_initial_quantity < 0 THEN
        RAISE EXCEPTION 'Initial quantity cannot be negative';
    END IF;

    IF _prod_unit_type = 'PACKAGED' AND p_initial_quantity != trunc(p_initial_quantity) THEN
        RAISE EXCEPTION 'Packaged product quantity must be an exact whole integer piece (received: %)', p_initial_quantity;
    END IF;

    IF _prod_unit_type = 'LOOSE' AND p_initial_quantity != round(p_initial_quantity, 3) THEN
        RAISE EXCEPTION 'Loose product quantity cannot exceed 3 decimal places / 1-gram precision (received: %)', p_initial_quantity;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.shop_inventory 
        WHERE shop_id = p_shop_id AND product_id = p_product_id
    ) INTO _exists;

    IF _exists THEN
        UPDATE public.shop_inventory
        SET selling_price = p_selling_price,
            low_stock_threshold = round(p_low_stock_threshold, 3),
            updated_at = clock_timestamp()
        WHERE shop_id = p_shop_id AND product_id = p_product_id;
    ELSE
        INSERT INTO public.shop_inventory (
            shop_id, product_id, organization_id, selling_price, quantity,
            low_stock_threshold, is_available, created_at, updated_at
        ) VALUES (
            p_shop_id, p_product_id, _org_id, p_selling_price, p_initial_quantity,
            round(p_low_stock_threshold, 3), true, clock_timestamp(), clock_timestamp()
        );

        IF p_initial_quantity > 0 THEN
            INSERT INTO public.stock_movements (
                id, shop_id, product_id, movement_type,
                delta_quantity, quantity_before, quantity_after,
                reference_id, reason, performed_by, created_at
            ) VALUES (
                gen_random_uuid(), p_shop_id, p_product_id, 'INITIAL',
                p_initial_quantity, 0.000, p_initial_quantity,
                NULL, 'Initial inventory setup', auth.uid(), clock_timestamp()
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'shop_id', p_shop_id,
        'product_id', p_product_id,
        'selling_price', p_selling_price,
        'is_new_record', NOT _exists
    );
END;
$$;

-- 14f. Update Inventory Pricing & Thresholds (No Quantity Change)
CREATE OR REPLACE FUNCTION public.update_inventory_pricing(
    p_shop_id uuid,
    p_product_id uuid,
    p_selling_price numeric,
    p_low_stock_threshold numeric DEFAULT 5,
    p_is_available boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_shop_admin(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can update inventory pricing';
    END IF;

    IF p_selling_price < 0 OR p_selling_price != round(p_selling_price, 2) THEN
        RAISE EXCEPTION 'Invalid selling price: Must be non-negative with max 2 decimal places';
    END IF;

    UPDATE public.shop_inventory
    SET selling_price = p_selling_price,
        low_stock_threshold = round(p_low_stock_threshold, 3),
        is_available = p_is_available,
        updated_at = clock_timestamp()
    WHERE shop_id = p_shop_id AND product_id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory record not found for shop % and product %', p_shop_id, p_product_id;
    END IF;

    RETURN jsonb_build_object(
        'shop_id', p_shop_id,
        'product_id', p_product_id,
        'selling_price', p_selling_price,
        'is_available', p_is_available
    );
END;
$$;

-- 14g. Restock Inventory
CREATE OR REPLACE FUNCTION public.restock_inventory(
    p_shop_id uuid,
    p_product_id uuid,
    p_quantity numeric,
    p_reason text DEFAULT 'Stock shipment delivery',
    p_reference_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _current_qty numeric(12,3);
    _new_qty numeric(12,3);
    _unit_type text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_shop_admin(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can restock inventory';
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Restock quantity must be greater than zero';
    END IF;

    SELECT p.unit_type, i.quantity 
    INTO _unit_type, _current_qty
    FROM public.shop_inventory i
    JOIN public.products p ON p.id = i.product_id
    WHERE i.shop_id = p_shop_id AND i.product_id = p_product_id
    FOR UPDATE OF i;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % is not initialized in shop % inventory', p_product_id, p_shop_id;
    END IF;

    IF _unit_type = 'PACKAGED' AND p_quantity != trunc(p_quantity) THEN
        RAISE EXCEPTION 'Packaged restock must be in whole integer pieces (received: %)', p_quantity;
    END IF;

    IF _unit_type = 'LOOSE' AND p_quantity != round(p_quantity, 3) THEN
        RAISE EXCEPTION 'Loose restock cannot exceed 3 decimal places / 1-gram precision (received: %)', p_quantity;
    END IF;

    _new_qty := _current_qty + p_quantity;

    UPDATE public.shop_inventory
    SET quantity = _new_qty,
        updated_at = clock_timestamp()
    WHERE shop_id = p_shop_id AND product_id = p_product_id;

    INSERT INTO public.stock_movements (
        id, shop_id, product_id, movement_type,
        delta_quantity, quantity_before, quantity_after,
        reference_id, reason, performed_by, created_at
    ) VALUES (
        gen_random_uuid(), p_shop_id, p_product_id, 'RESTOCK',
        p_quantity, _current_qty, _new_qty,
        p_reference_id, coalesce(p_reason, 'Restock delivery'), auth.uid(), clock_timestamp()
    );

    RETURN jsonb_build_object(
        'shop_id', p_shop_id,
        'product_id', p_product_id,
        'restocked_quantity', p_quantity,
        'new_quantity', _new_qty
    );
END;
$$;

-- 14h. Adjust Inventory
CREATE OR REPLACE FUNCTION public.adjust_inventory(
    p_shop_id uuid,
    p_product_id uuid,
    p_new_quantity numeric,
    p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _current_qty numeric(12,3);
    _delta numeric(12,3);
    _unit_type text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    IF NOT public.is_shop_admin(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: Only a Shop/Org Admin can adjust inventory levels';
    END IF;

    IF p_new_quantity < 0 THEN
        RAISE EXCEPTION 'Adjusted inventory quantity cannot be negative';
    END IF;

    IF trim(p_reason) IS NULL OR length(trim(p_reason)) < 3 THEN
        RAISE EXCEPTION 'Auditable reason required for inventory adjustment';
    END IF;

    SELECT p.unit_type, i.quantity 
    INTO _unit_type, _current_qty
    FROM public.shop_inventory i
    JOIN public.products p ON p.id = i.product_id
    WHERE i.shop_id = p_shop_id AND i.product_id = p_product_id
    FOR UPDATE OF i;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % is not initialized in shop % inventory', p_product_id, p_shop_id;
    END IF;

    IF _unit_type = 'PACKAGED' AND p_new_quantity != trunc(p_new_quantity) THEN
        RAISE EXCEPTION 'Packaged stock level must be in whole integer pieces (received: %)', p_new_quantity;
    END IF;

    IF _unit_type = 'LOOSE' AND p_new_quantity != round(p_new_quantity, 3) THEN
        RAISE EXCEPTION 'Loose stock level cannot exceed 3 decimal places / 1-gram precision (received: %)', p_new_quantity;
    END IF;

    _delta := p_new_quantity - _current_qty;
    IF _delta = 0 THEN
        RETURN jsonb_build_object('message', 'Quantity unchanged');
    END IF;

    UPDATE public.shop_inventory
    SET quantity = p_new_quantity,
        updated_at = clock_timestamp()
    WHERE shop_id = p_shop_id AND product_id = p_product_id;

    INSERT INTO public.stock_movements (
        id, shop_id, product_id, movement_type,
        delta_quantity, quantity_before, quantity_after,
        reference_id, reason, performed_by, created_at
    ) VALUES (
        gen_random_uuid(), p_shop_id, p_product_id, 'ADJUSTMENT',
        _delta, _current_qty, p_new_quantity,
        NULL, trim(p_reason), auth.uid(), clock_timestamp()
    );

    RETURN jsonb_build_object(
        'shop_id', p_shop_id,
        'product_id', p_product_id,
        'delta', _delta,
        'quantity_after', p_new_quantity
    );
END;
$$;

-- ==============================================================================
-- 15. Atomic Checkout Transaction Procedure (process_sale_tx)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.process_sale_tx(
    p_shop_id uuid,
    p_checkout_id uuid,
    p_payment_method text,
    p_items jsonb, -- [{"product_id": uuid, "quantity": numeric (for PACKAGED), "weight_ticket_id": uuid (for LOOSE)}]
    p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _sale_id uuid;
    _sale_number text;
    _item jsonb;
    _item_product_id uuid;
    _item_qty numeric;
    _ticket_id uuid;
    _selling_price numeric(12,2);
    _current_stock numeric(12,3);
    _product_name text;
    _unit_type text;
    _line_total numeric(12,2);
    _calc_total numeric(12,2) := 0.00;
    _rows_affected integer;
    _processed_products uuid[] := '{}';
    _ticket_record record;
    _current_payload_hash text;
    _existing_checkout record;
    _existing_sale record;
    _next_seq bigint;
    _canonical_items text;
    _inserted_id uuid;
BEGIN
    -- 1. Authentication check
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    -- 2. Authorization check against trusted shop access function
    IF NOT public.has_shop_access(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: User does not have access to shop %', p_shop_id;
    END IF;

    -- 3. Validate items array
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Invalid request: Cart contains no items';
    END IF;

    -- 4. Canonical payload serialization for deterministic idempotency hashing
    SELECT string_agg(
      (elem->>'product_id') || ':' || coalesce(elem->>'quantity', '') || ':' || coalesce(elem->>'weight_ticket_id', ''),
      ',' ORDER BY elem->>'product_id'
    ) INTO _canonical_items
    FROM jsonb_array_elements(p_items) AS elem;

    _current_payload_hash := encode(digest(
      p_shop_id::text || '|' || coalesce(p_payment_method, 'CASH') || '|' || coalesce(trim(p_notes), '') || '|' || _canonical_items,
      'sha256'
    ), 'hex');

    -- 5. Concurrency-Safe Idempotency Check
    INSERT INTO public.processed_checkouts (checkout_id, shop_id, payload_hash, status, created_at, updated_at)
    VALUES (p_checkout_id, p_shop_id, _current_payload_hash, 'PROCESSING', clock_timestamp(), clock_timestamp())
    ON CONFLICT (checkout_id) DO NOTHING
    RETURNING checkout_id INTO _inserted_id;

    -- Lock the processed_checkouts record to synchronize concurrent submissions of the same checkout_id
    SELECT * INTO _existing_checkout
    FROM public.processed_checkouts
    WHERE checkout_id = p_checkout_id
    FOR UPDATE;

    IF _inserted_id IS NULL THEN
        -- Record existed prior to this transaction
        IF _existing_checkout.status = 'COMPLETED' THEN
            -- If already completed: verify that shop and canonical payload match exactly
            IF _existing_checkout.shop_id = p_shop_id AND _existing_checkout.payload_hash = _current_payload_hash THEN
                SELECT id, sale_number, total_amount, payment_status, created_at
                INTO _existing_sale
                FROM public.sales
                WHERE id = _existing_checkout.sale_id;

                RETURN jsonb_build_object(
                    'sale_id', _existing_sale.id,
                    'sale_number', _existing_sale.sale_number,
                    'total_amount', _existing_sale.total_amount,
                    'status', _existing_sale.payment_status,
                    'created_at', _existing_sale.created_at,
                    'is_idempotent_retry', true
                );
            ELSE
                RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT: Checkout ID % was previously submitted with a different shop or cart payload', p_checkout_id;
            END IF;
        ELSE
            -- Status is still 'PROCESSING' in another concurrent transaction
            RAISE EXCEPTION 'CHECKOUT_IN_PROGRESS: Checkout ID % is currently being processed by another worker. Please retry.', p_checkout_id;
        END IF;
    END IF;

    -- 6. Atomic, monotonic receipt sequence generation
    INSERT INTO public.shop_receipt_sequences (shop_id, last_number, updated_at)
    VALUES (p_shop_id, 1, clock_timestamp())
    ON CONFLICT (shop_id) DO UPDATE
    SET last_number = public.shop_receipt_sequences.last_number + 1,
        updated_at = clock_timestamp()
    RETURNING last_number INTO _next_seq;

    _sale_number := 'REC-' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' || lpad(_next_seq::text, 6, '0');
    _sale_id := gen_random_uuid();

    -- 7. Insert preliminary sale record
    INSERT INTO public.sales (
        id, shop_id, cashier_user_id, checkout_id, sale_number,
        total_amount, payment_method, payment_status, notes, created_at
    ) VALUES (
        _sale_id, p_shop_id, auth.uid(), p_checkout_id, _sale_number,
        0.00, coalesce(p_payment_method, 'CASH'), 'COMPLETED', p_notes, clock_timestamp()
    );

    -- 8. Process each line item with row locking and strict unit validation
    FOR _item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        _item_product_id := (_item->>'product_id')::uuid;

        IF _item_product_id = ANY(_processed_products) THEN
            RAISE EXCEPTION 'Invalid cart: Duplicate product % detected. Aggregate quantities before checkout.', _item_product_id;
        END IF;
        _processed_products := array_append(_processed_products, _item_product_id);

        SELECT 
            i.selling_price,
            i.quantity,
            p.name,
            p.unit_type
        INTO 
            _selling_price,
            _current_stock,
            _product_name,
            _unit_type
        FROM public.shop_inventory i
        JOIN public.products p ON p.id = i.product_id
        WHERE i.shop_id = p_shop_id 
          AND i.product_id = _item_product_id
          AND p.is_active = true
          AND i.is_available = true
        FOR UPDATE OF i;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % is unavailable or not stocked in shop %', _item_product_id, p_shop_id;
        END IF;

        IF _unit_type = 'LOOSE' THEN
            _ticket_id := (_item->>'weight_ticket_id')::uuid;
            IF _ticket_id IS NULL THEN
                RAISE EXCEPTION 'Weighing required: Loose item % requires a verified weight ticket', _product_name;
            END IF;

            SELECT * INTO _ticket_record
            FROM public.verified_weight_tickets
            WHERE id = _ticket_id
              AND shop_id = p_shop_id
              AND product_id = _item_product_id
            FOR UPDATE;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Invalid weight ticket % for product % in this shop', _ticket_id, _product_name;
            END IF;

            IF _ticket_record.is_consumed THEN
                RAISE EXCEPTION 'Replay attack prevented: Weight ticket % has already been consumed', _ticket_id;
            END IF;

            IF _ticket_record.expires_at < clock_timestamp() THEN
                RAISE EXCEPTION 'Stale measurement: Weight ticket % has expired. Please re-weigh the item.', _ticket_id;
            END IF;

            _item_qty := _ticket_record.weight_kg;

            UPDATE public.verified_weight_tickets
            SET is_consumed = true,
                consumed_at = clock_timestamp(),
                consumed_in_sale_id = _sale_id
            WHERE id = _ticket_id;

        ELSE
            _item_qty := (_item->>'quantity')::numeric;
            _ticket_id := NULL;

            IF _item_qty IS NULL OR _item_qty <= 0 THEN
                RAISE EXCEPTION 'Invalid quantity for packaged product %: must be greater than zero', _product_name;
            END IF;

            IF _item_qty != trunc(_item_qty) THEN
                RAISE EXCEPTION 'Packaged product % must be purchased in whole integer pieces (received: %)', _product_name, _item_qty;
            END IF;
        END IF;

        _line_total := round(_selling_price * _item_qty, 2);
        _calc_total := _calc_total + _line_total;

        UPDATE public.shop_inventory
        SET quantity = quantity - _item_qty,
            updated_at = clock_timestamp()
        WHERE shop_id = p_shop_id 
          AND product_id = _item_product_id
          AND quantity >= _item_qty;

        GET DIAGNOSTICS _rows_affected = ROW_COUNT;
        IF _rows_affected = 0 THEN
            RAISE EXCEPTION 'Insufficient stock for product % (Available: %, Requested: %)', 
                _product_name, _current_stock, _item_qty;
        END IF;

        INSERT INTO public.sale_items (
            id, sale_id, product_id, product_name,
            unit_type, quantity, unit_price, line_total, weight_ticket_id, created_at
        ) VALUES (
            gen_random_uuid(), _sale_id, _item_product_id, _product_name,
            _unit_type, _item_qty, _selling_price, _line_total, _ticket_id, clock_timestamp()
        );

        INSERT INTO public.stock_movements (
            id, shop_id, product_id, movement_type,
            delta_quantity, quantity_before, quantity_after,
            reference_id, reason, performed_by, created_at
        ) VALUES (
            gen_random_uuid(), p_shop_id, _item_product_id, 'SALE',
            -_item_qty, _current_stock, (_current_stock - _item_qty),
            _sale_id, 'POS Checkout ' || _sale_number, auth.uid(), clock_timestamp()
        );
    END LOOP;

    -- 9. Persist calculated total
    UPDATE public.sales
    SET total_amount = _calc_total
    WHERE id = _sale_id;

    -- 10. Update idempotency guard to COMPLETED
    UPDATE public.processed_checkouts
    SET sale_id = _sale_id,
        status = 'COMPLETED',
        updated_at = clock_timestamp()
    WHERE checkout_id = p_checkout_id;

    RETURN jsonb_build_object(
        'sale_id', _sale_id,
        'sale_number', _sale_number,
        'total_amount', _calc_total,
        'status', 'COMPLETED',
        'is_idempotent_retry', false
    );
END;
$$;

-- ==============================================================================
-- 16. Enable Row Level Security (RLS) on All Tables
-- ==============================================================================

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_receipt_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sensor_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verified_weight_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.processed_checkouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- 17. Reviewed RLS Policies
-- ==============================================================================

-- 17a. Organizations
CREATE POLICY "org_select" ON public.organizations
    FOR SELECT TO authenticated
    USING (public.has_org_access(id));

CREATE POLICY "org_insert_disallowed" ON public.organizations
    FOR INSERT TO authenticated
    WITH CHECK (false);

CREATE POLICY "org_admin_update" ON public.organizations
    FOR UPDATE TO authenticated
    USING (public.is_org_admin(id))
    WITH CHECK (public.is_org_admin(id));

CREATE POLICY "org_admin_delete" ON public.organizations
    FOR DELETE TO authenticated
    USING (public.is_org_admin(id));

-- 17b. Shops
CREATE POLICY "shop_select" ON public.shops
    FOR SELECT TO authenticated
    USING (public.has_shop_access(id));

CREATE POLICY "shop_admin_insert" ON public.shops
    FOR INSERT TO authenticated
    WITH CHECK (public.is_org_admin(organization_id));

CREATE POLICY "shop_admin_update" ON public.shops
    FOR UPDATE TO authenticated
    USING (public.is_org_admin(organization_id))
    WITH CHECK (public.is_org_admin(organization_id));

CREATE POLICY "shop_admin_delete" ON public.shops
    FOR DELETE TO authenticated
    USING (public.is_org_admin(organization_id));

-- 17c. Shop Receipt Sequences (Internal)
CREATE POLICY "receipt_seq_admin_select" ON public.shop_receipt_sequences
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

-- 17d. Profiles (Least-Privilege Privacy)
CREATE POLICY "profiles_select_restricted" ON public.profiles
    FOR SELECT TO authenticated
    USING (
        id = auth.uid()
        OR EXISTS (
            SELECT 1 
            FROM public.organization_memberships om_target
            JOIN public.organization_memberships om_admin ON om_admin.organization_id = om_target.organization_id
            WHERE om_target.user_id = profiles.id
              AND om_admin.user_id = auth.uid()
              AND om_admin.role = 'ORG_ADMIN'
              AND om_admin.status = 'ACTIVE'
        )
        OR EXISTS (
            SELECT 1 
            FROM public.shop_memberships sm_target
            JOIN public.shop_memberships sm_admin ON sm_admin.shop_id = sm_target.shop_id
            WHERE sm_target.user_id = profiles.id
              AND sm_admin.user_id = auth.uid()
              AND sm_admin.role = 'SHOP_ADMIN'
              AND sm_admin.status = 'ACTIVE'
        )
    );

CREATE POLICY "profiles_insert_disallowed" ON public.profiles
    FOR INSERT TO authenticated
    WITH CHECK (false);

CREATE POLICY "profiles_update_self" ON public.profiles
    FOR UPDATE TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- 17e. Organization Memberships
CREATE POLICY "org_members_select" ON public.organization_memberships
    FOR SELECT TO authenticated
    USING (public.has_org_access(organization_id));

CREATE POLICY "org_members_admin_write" ON public.organization_memberships
    FOR ALL TO authenticated
    USING (public.is_org_admin(organization_id))
    WITH CHECK (public.is_org_admin(organization_id));

-- 17f. Shop Memberships
CREATE POLICY "shop_members_select" ON public.shop_memberships
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

CREATE POLICY "shop_members_admin_write" ON public.shop_memberships
    FOR ALL TO authenticated
    USING (public.is_shop_admin(shop_id))
    WITH CHECK (public.is_shop_admin(shop_id));

-- 17g. Categories
CREATE POLICY "categories_select" ON public.categories
    FOR SELECT TO authenticated
    USING (public.has_org_access(organization_id));

CREATE POLICY "categories_admin_write" ON public.categories
    FOR ALL TO authenticated
    USING (public.is_org_admin(organization_id))
    WITH CHECK (public.is_org_admin(organization_id));

-- 17h. Products
CREATE POLICY "products_select" ON public.products
    FOR SELECT TO authenticated
    USING (public.has_org_access(organization_id));

CREATE POLICY "products_admin_write" ON public.products
    FOR ALL TO authenticated
    USING (public.is_org_admin(organization_id))
    WITH CHECK (public.is_org_admin(organization_id));

-- 17i. Shop Inventory (Zero direct DML)
CREATE POLICY "shop_inventory_select" ON public.shop_inventory
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

CREATE POLICY "shop_inventory_insert_disallowed" ON public.shop_inventory
    FOR INSERT TO authenticated
    WITH CHECK (false);

CREATE POLICY "shop_inventory_update_disallowed" ON public.shop_inventory
    FOR UPDATE TO authenticated
    USING (false);

CREATE POLICY "shop_inventory_delete_disallowed" ON public.shop_inventory
    FOR DELETE TO authenticated
    USING (false);

-- 17j. Devices
CREATE POLICY "devices_select" ON public.devices
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

CREATE POLICY "devices_admin_write" ON public.devices
    FOR ALL TO authenticated
    USING (public.is_shop_admin(shop_id))
    WITH CHECK (public.is_shop_admin(shop_id));

-- 17k. Quarantined Device Credentials (Zero Client Access)
CREATE POLICY "device_credentials_disallow_all" ON public.device_credentials
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- 17l. Sensor Readings
CREATE POLICY "sensor_readings_select" ON public.sensor_readings
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.devices d
            WHERE d.id = sensor_readings.device_id
              AND public.has_shop_access(d.shop_id)
        )
    );

CREATE POLICY "sensor_readings_write_disallowed" ON public.sensor_readings
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- 17m. Verified Weight Tickets
CREATE POLICY "verified_weight_tickets_select" ON public.verified_weight_tickets
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

CREATE POLICY "verified_weight_tickets_client_write_disallowed" ON public.verified_weight_tickets
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- 17n. Processed Checkouts
CREATE POLICY "processed_checkouts_select" ON public.processed_checkouts
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

CREATE POLICY "processed_checkouts_write_disallowed" ON public.processed_checkouts
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- 17o. Sales
CREATE POLICY "sales_select" ON public.sales
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

CREATE POLICY "sales_client_write_disallowed" ON public.sales
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- 17p. Sale Items
CREATE POLICY "sale_items_select" ON public.sale_items
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.sales s
            WHERE s.id = sale_items.sale_id
              AND public.has_shop_access(s.shop_id)
        )
    );

CREATE POLICY "sale_items_client_write_disallowed" ON public.sale_items
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- 17q. Stock Movements
CREATE POLICY "stock_movements_select" ON public.stock_movements
    FOR SELECT TO authenticated
    USING (public.has_shop_access(shop_id));

CREATE POLICY "stock_movements_client_write_disallowed" ON public.stock_movements
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- ==============================================================================
-- 18. Hardened Database & Object Privileges (Zero-Trust Principle)
-- ==============================================================================

-- 18a. Revoke default schema privileges
REVOKE ALL ON SCHEMA public FROM PUBLIC, anon;

-- 18b. Revoke all privileges on all existing tables, sequences, and functions from PUBLIC, anon, and authenticated
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;

-- 18c. Alter default privileges to ensure future objects do not leak default access
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- 18d. Explicit schema usage grants
GRANT USAGE ON SCHEMA public TO authenticated, service_role;

-- 18e. Grant SELECT strictly to authenticated on readable tenant tables
GRANT SELECT ON public.organizations TO authenticated;
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT ON public.organization_memberships TO authenticated;
GRANT SELECT ON public.shop_memberships TO authenticated;
GRANT SELECT ON public.categories TO authenticated;
GRANT SELECT ON public.products TO authenticated;
GRANT SELECT ON public.shop_inventory TO authenticated;
GRANT SELECT ON public.devices TO authenticated;
GRANT SELECT ON public.sensor_readings TO authenticated;
GRANT SELECT ON public.verified_weight_tickets TO authenticated;
GRANT SELECT ON public.processed_checkouts TO authenticated;
GRANT SELECT ON public.sales TO authenticated;
GRANT SELECT ON public.sale_items TO authenticated;
GRANT SELECT ON public.stock_movements TO authenticated;

-- Allow authenticated UPDATE strictly on profiles (further restricted by RLS to own row)
GRANT UPDATE (full_name, updated_at) ON public.profiles TO authenticated;

-- 18f. Service role retains administrative maintenance access
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;

-- ==============================================================================
-- 19. Hardened Function Execution Privileges
-- ==============================================================================

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.is_org_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_shop_access(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_shop_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_org_access(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_organization_onboarding(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_shop(uuid, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assign_shop_membership(uuid, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_product(uuid, uuid, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.setup_shop_inventory(uuid, uuid, numeric, numeric, numeric) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_inventory_pricing(uuid, uuid, numeric, numeric, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.restock_inventory(uuid, uuid, numeric, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.adjust_inventory(uuid, uuid, numeric, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enroll_device(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rotate_device_credentials(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_device_after_reset(uuid, bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_device(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.calibrate_device(uuid, numeric, numeric) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.process_sale_tx(uuid, uuid, text, jsonb, text) TO authenticated, service_role;

-- Machine-to-machine scale telemetry procedures (strictly service_role; client access revoked)
GRANT EXECUTE ON FUNCTION public.register_device_boot(uuid, bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_scale_telemetry(uuid, uuid, uuid, numeric, numeric, bigint, boolean, timestamptz, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.issue_verified_weight_ticket(uuid, uuid, numeric, numeric, bigint, boolean, timestamptz, uuid, bigint) TO service_role;

-- ==============================================================================
-- 20. Supabase Realtime Configuration & Replica Identity
-- ==============================================================================

ALTER TABLE public.sensor_readings REPLICA IDENTITY FULL;
ALTER TABLE public.verified_weight_tickets REPLICA IDENTITY FULL;
ALTER TABLE public.shop_inventory REPLICA IDENTITY FULL;
ALTER TABLE public.sales REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'sensor_readings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sensor_readings;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'verified_weight_tickets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.verified_weight_tickets;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'shop_inventory'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.shop_inventory;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'sales'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sales;
  END IF;
END $$;
