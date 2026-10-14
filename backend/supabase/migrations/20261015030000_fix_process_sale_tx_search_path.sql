-- ==============================================================================
-- SmartShelf V2 - Migration: Explicit extensions namespace for process_sale_tx
-- Migration: 20261015030000_fix_process_sale_tx_search_path.sql
--
-- ARCHITECTURAL RATIONALE:
-- In Supabase PostgreSQL, pgcrypto functions (gen_random_bytes, digest) reside in
-- the extensions schema. The base migration declared process_sale_tx with
-- search_path = public, pg_catalog, causing runtime failures when computing
-- the checkout idempotency hash via digest().
--
-- This migration updates search_path to (public, extensions, pg_catalog) and
-- explicitly qualifies extensions.digest() to guarantee deterministic, tamper-proof
-- checkout execution across all hosted Supabase environments.
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
SET search_path = public, extensions, pg_catalog
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

    _current_payload_hash := encode(extensions.digest(
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

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.process_sale_tx(uuid, uuid, text, jsonb, text) TO authenticated, service_role;
