-- ==============================================================================
-- SmartShelf V2 - AI Shopkeeper Assistant Server Analytics RPC
-- Migration: 20261015010000_ai_shopkeeper_assistant_rpc.sql
--
-- SECURITY & INTEGRITY INVARIANTS:
-- 1. SECURITY DEFINER procedure with search_path = public, pg_catalog.
-- 2. Strictly enforces public.has_shop_access(p_shop_id) - blocks cross-tenant leakage.
-- 3. Cross-shop trend analytics strictly restricted to verified ORG_ADMINs.
-- 4. Computes deterministic, auditable business metrics directly from source tables:
--    sales, sale_items, shop_inventory, and stock_movements.
-- 5. No client-supplied unverified values; strict type-safe jsonb response.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.get_shopkeeper_assistant_analytics(
    p_shop_id uuid,
    p_intent text DEFAULT 'GENERAL_OVERVIEW'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    _org_id uuid;
    _shop_name text;
    _currency text;
    _now timestamptz := clock_timestamp();
    _start_of_today timestamptz;
    _start_of_month timestamptz;
    _start_of_this_week timestamptz;
    _start_of_last_week timestamptz;
    _30_days_ago timestamptz;
    _14_days_ago timestamptz;
    _result jsonb;
BEGIN
    -- 1. Authentication check
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Sign-in required';
    END IF;

    -- 2. Multi-Tenant Authorization check
    IF NOT public.has_shop_access(p_shop_id) THEN
        RAISE EXCEPTION 'Unauthorized: You do not have access to this store';
    END IF;

    -- 3. Resolve Shop Metadata
    SELECT organization_id, name, currency
    INTO _org_id, _shop_name, _currency
    FROM public.shops
    WHERE id = p_shop_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop not found';
    END IF;

    _start_of_today := date_trunc('day', _now);
    _start_of_month := date_trunc('month', _now);
    _start_of_this_week := _now - interval '7 days';
    _start_of_last_week := _now - interval '14 days';
    _30_days_ago := _now - interval '30 days';
    _14_days_ago := _now - interval '14 days';

    -- 4. Execute deterministic analytics based on intent
    CASE upper(trim(p_intent))

    WHEN 'TODAY_SALES' THEN
        SELECT jsonb_build_object(
            'intent', 'TODAY_SALES',
            'shop_name', _shop_name,
            'currency', _currency,
            'date', to_char(_start_of_today, 'YYYY-MM-DD'),
            'transaction_count', COALESCE(COUNT(s.id), 0),
            'total_revenue', COALESCE(SUM(s.total_amount), 0.00),
            'average_order_value', CASE WHEN COUNT(s.id) > 0 THEN ROUND(COALESCE(AVG(s.total_amount), 0.00), 2) ELSE 0.00 END,
            'cash_revenue', COALESCE(SUM(CASE WHEN s.payment_method = 'CASH' THEN s.total_amount ELSE 0.00 END), 0.00),
            'digital_revenue', COALESCE(SUM(CASE WHEN s.payment_method IN ('UPI', 'CARD') THEN s.total_amount ELSE 0.00 END), 0.00),
            'top_product_today', (
                SELECT jsonb_build_object(
                    'name', si.product_name,
                    'quantity', SUM(si.quantity),
                    'unit_type', si.unit_type
                )
                FROM public.sale_items si
                JOIN public.sales s2 ON s2.id = si.sale_id
                WHERE s2.shop_id = p_shop_id AND s2.created_at >= _start_of_today
                GROUP BY si.product_name, si.unit_type
                ORDER BY SUM(si.quantity) DESC
                LIMIT 1
            )
        )
        INTO _result
        FROM public.sales s
        WHERE s.shop_id = p_shop_id AND s.created_at >= _start_of_today;

    WHEN 'MONTH_SALES' THEN
        SELECT jsonb_build_object(
            'intent', 'MONTH_SALES',
            'shop_name', _shop_name,
            'currency', _currency,
            'month', to_char(_start_of_month, 'FMMonth YYYY'),
            'transaction_count', COALESCE(COUNT(s.id), 0),
            'total_revenue', COALESCE(SUM(s.total_amount), 0.00),
            'daily_average', CASE 
                WHEN EXTRACT(DAY FROM _now) > 0 THEN 
                    ROUND(COALESCE(SUM(s.total_amount), 0.00) / EXTRACT(DAY FROM _now), 2)
                ELSE 0.00 
            END
        )
        INTO _result
        FROM public.sales s
        WHERE s.shop_id = p_shop_id AND s.created_at >= _start_of_month;

    WHEN 'PERIOD_COMPARE' THEN
        WITH this_week AS (
            SELECT 
                COALESCE(SUM(total_amount), 0.00) AS revenue,
                COUNT(id) AS orders
            FROM public.sales
            WHERE shop_id = p_shop_id AND created_at >= _start_of_this_week
        ),
        last_week AS (
            SELECT 
                COALESCE(SUM(total_amount), 0.00) AS revenue,
                COUNT(id) AS orders
            FROM public.sales
            WHERE shop_id = p_shop_id AND created_at >= _start_of_last_week AND created_at < _start_of_this_week
        )
        SELECT jsonb_build_object(
            'intent', 'PERIOD_COMPARE',
            'shop_name', _shop_name,
            'currency', _currency,
            'this_week_revenue', tw.revenue,
            'this_week_orders', tw.orders,
            'last_week_revenue', lw.revenue,
            'last_week_orders', lw.orders,
            'revenue_difference', (tw.revenue - lw.revenue),
            'percentage_change', CASE 
                WHEN lw.revenue > 0 THEN ROUND(((tw.revenue - lw.revenue) / lw.revenue) * 100.0, 1)
                WHEN tw.revenue > 0 THEN 100.0
                ELSE 0.0
            END
        )
        INTO _result
        FROM this_week tw, last_week lw;

    WHEN 'TOP_SELLING' THEN
        WITH ranked_items AS (
            SELECT 
                si.product_name,
                si.unit_type,
                SUM(si.quantity) AS total_quantity,
                SUM(si.line_total) AS total_revenue
            FROM public.sale_items si
            JOIN public.sales s ON s.id = si.sale_id
            WHERE s.shop_id = p_shop_id AND s.created_at >= _30_days_ago
            GROUP BY si.product_name, si.unit_type
            ORDER BY SUM(si.quantity) DESC
            LIMIT 5
        )
        SELECT jsonb_build_object(
            'intent', 'TOP_SELLING',
            'shop_name', _shop_name,
            'currency', _currency,
            'period', 'last 30 days',
            'items', COALESCE(jsonb_agg(jsonb_build_object(
                'name', ri.product_name,
                'unit_type', ri.unit_type,
                'total_quantity', ri.total_quantity,
                'total_revenue', ri.total_revenue
            )), '[]'::jsonb)
        )
        INTO _result
        FROM ranked_items ri;

    WHEN 'LOW_STOCK' THEN
        WITH stock_status AS (
            SELECT 
                p.name AS product_name,
                p.unit_type,
                inv.quantity,
                inv.low_stock_threshold,
                CASE 
                    WHEN inv.quantity <= 0 THEN 'OUT_OF_STOCK'
                    WHEN inv.quantity <= inv.low_stock_threshold THEN 'LOW_STOCK'
                    ELSE 'HEALTHY'
                END AS stock_state
            FROM public.shop_inventory inv
            JOIN public.products p ON p.id = inv.product_id
            WHERE inv.shop_id = p_shop_id
        )
        SELECT jsonb_build_object(
            'intent', 'LOW_STOCK',
            'shop_name', _shop_name,
            'currency', _currency,
            'total_products', COUNT(*),
            'out_of_stock_count', COUNT(*) FILTER (WHERE stock_state = 'OUT_OF_STOCK'),
            'low_stock_count', COUNT(*) FILTER (WHERE stock_state = 'LOW_STOCK'),
            'out_of_stock_items', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'name', product_name,
                    'quantity', quantity,
                    'threshold', low_stock_threshold,
                    'unit_type', unit_type
                )) FROM stock_status WHERE stock_state = 'OUT_OF_STOCK'
            ), '[]'::jsonb),
            'low_stock_items', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'name', product_name,
                    'quantity', quantity,
                    'threshold', low_stock_threshold,
                    'unit_type', unit_type
                )) FROM stock_status WHERE stock_state = 'LOW_STOCK'
            ), '[]'::jsonb)
        )
        INTO _result
        FROM stock_status;

    WHEN 'RESTOCK' THEN
        WITH restock_candidates AS (
            SELECT 
                inv.product_id,
                p.name AS product_name,
                p.unit_type,
                inv.quantity AS current_stock,
                inv.low_stock_threshold AS threshold,
                COALESCE((
                    SELECT SUM(si.quantity)
                    FROM public.sale_items si
                    JOIN public.sales s ON s.id = si.sale_id
                    WHERE s.shop_id = p_shop_id 
                      AND si.product_id = inv.product_id 
                      AND s.created_at >= _14_days_ago
                ), 0) AS units_sold_14d
            FROM public.shop_inventory inv
            JOIN public.products p ON p.id = inv.product_id
            WHERE inv.shop_id = p_shop_id AND inv.quantity <= inv.low_stock_threshold
        )
        SELECT jsonb_build_object(
            'intent', 'RESTOCK',
            'shop_name', _shop_name,
            'currency', _currency,
            'item_count', COUNT(*),
            'recommendations', COALESCE(jsonb_agg(jsonb_build_object(
                'name', rc.product_name,
                'unit_type', rc.unit_type,
                'current_stock', rc.current_stock,
                'threshold', rc.threshold,
                'units_sold_14d', rc.units_sold_14d,
                'suggested_restock', GREATEST(
                    CEIL(rc.threshold * 2.0 - rc.current_stock),
                    CEIL(rc.units_sold_14d)
                ),
                'urgency', CASE 
                    WHEN rc.current_stock <= 0 THEN 'CRITICAL (Out of Stock)'
                    ELSE 'HIGH (Below Safety Threshold)'
                END
            )), '[]'::jsonb)
        )
        INTO _result
        FROM restock_candidates rc;

    WHEN 'SLOW_MOVING' THEN
        WITH inventory_sales AS (
            SELECT 
                p.name AS product_name,
                p.unit_type,
                inv.quantity AS current_stock,
                FLOOR(EXTRACT(EPOCH FROM (_now - inv.created_at)) / 86400) AS days_stocked,
                COALESCE((
                    SELECT SUM(si.quantity)
                    FROM public.sale_items si
                    JOIN public.sales s ON s.id = si.sale_id
                    WHERE s.shop_id = p_shop_id 
                      AND si.product_id = inv.product_id 
                      AND s.created_at >= _30_days_ago
                ), 0) AS units_sold_30d
            FROM public.shop_inventory inv
            JOIN public.products p ON p.id = inv.product_id
            WHERE inv.shop_id = p_shop_id
        )
        SELECT jsonb_build_object(
            'intent', 'SLOW_MOVING',
            'shop_name', _shop_name,
            'currency', _currency,
            'period', 'last 30 days',
            'items', COALESCE(jsonb_agg(jsonb_build_object(
                'name', product_name,
                'unit_type', unit_type,
                'current_stock', current_stock,
                'days_stocked', days_stocked,
                'units_sold_30d', units_sold_30d
            )), '[]'::jsonb)
        )
        INTO _result
        FROM inventory_sales
        WHERE units_sold_30d <= 1 AND days_stocked >= 7;

    WHEN 'CROSS_SHOP' THEN
        IF NOT public.is_org_admin(_org_id) THEN
            _result := jsonb_build_object(
                'intent', 'CROSS_SHOP',
                'authorized', false,
                'message', 'Cross-shop trends and multi-branch network analytics are restricted to organization administrators to protect store data privacy.'
            );
        ELSE
            SELECT jsonb_build_object(
                'intent', 'CROSS_SHOP',
                'authorized', true,
                'shop_name', _shop_name,
                'currency', _currency,
                'total_organization_branches', COUNT(DISTINCT s.id),
                'total_network_today_revenue', COALESCE(SUM(sa.total_amount), 0.00)
            )
            INTO _result
            FROM public.shops s
            LEFT JOIN public.sales sa ON sa.shop_id = s.id AND sa.created_at >= _start_of_today
            WHERE s.organization_id = _org_id;
        END IF;

    ELSE -- GENERAL_OVERVIEW
        WITH today_stats AS (
            SELECT 
                COALESCE(COUNT(id), 0) AS today_orders,
                COALESCE(SUM(total_amount), 0.00) AS today_revenue
            FROM public.sales
            WHERE shop_id = p_shop_id AND created_at >= _start_of_today
        ),
        stock_stats AS (
            SELECT 
                COUNT(*) AS total_items,
                COUNT(*) FILTER (WHERE quantity <= 0) AS out_of_stock,
                COUNT(*) FILTER (WHERE quantity > 0 AND quantity <= low_stock_threshold) AS low_stock
            FROM public.shop_inventory
            WHERE shop_id = p_shop_id
        )
        SELECT jsonb_build_object(
            'intent', 'GENERAL_OVERVIEW',
            'shop_name', _shop_name,
            'currency', _currency,
            'today_orders', ts.today_orders,
            'today_revenue', ts.today_revenue,
            'total_items', ss.total_items,
            'out_of_stock_count', ss.out_of_stock,
            'low_stock_count', ss.low_stock
        )
        INTO _result
        FROM today_stats ts, stock_stats ss;

    END CASE;

    RETURN _result;
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.get_shopkeeper_assistant_analytics(uuid, text) TO authenticated;
