-- =====================================================================
-- Blinkit 10-Minute Grocery Delivery Database
-- Phase 4: Indexes & Statistics
-- Every index lists: target queries, index type, and column order rationale.
-- =====================================================================

SET search_path TO blinkit;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------
-- 1. dark_stores
-- ---------------------------------------------------------------------

-- Serves: R01 (nearest active dark store within lat/lon bounding box)
-- Type: Partial covering B-tree. Only active stores are queried; INCLUDE avoids heap lookups.
CREATE INDEX idx_dark_stores_active_coords
    ON dark_stores (latitude, longitude)
    INCLUDE (store_id, store_code)
    WHERE is_active;

-- ---------------------------------------------------------------------
-- 2. products
-- ---------------------------------------------------------------------

-- Serves: R03 (case-insensitive substring search: product_name ILIKE '%milk%')
-- Type: GIN trigram index (pg_trgm). Standard B-tree cannot accelerate leading-wildcard ILIKE.
CREATE INDEX idx_products_name_trgm
    ON products USING gin (product_name gin_trgm_ops);

-- Serves: R02, R19 (filter products by category_id and retrieve product_name)
-- Type: Covering B-tree. category_id equality first, product_id for join, product_name included.
CREATE INDEX idx_products_category_cover
    ON products (category_id, product_id)
    INCLUDE (product_name);

-- ---------------------------------------------------------------------
-- 3. store_inventory
-- ---------------------------------------------------------------------

-- Serves: R02, R03 (in-stock items at a specific store, pre-sorted by selling_price)
-- Type: Partial covering B-tree (quantity_on_hand > 0). Equality store_id first, sort key
--       selling_price second, product_id third so R02 avoids sorting and heap fetches.
CREATE INDEX idx_store_inv_instock_store_price
    ON store_inventory (store_id, selling_price, product_id)
    INCLUDE (quantity_on_hand)
    WHERE quantity_on_hand > 0;

-- Serves: R04 (stock & price of a single product across stores)
-- Type: Covering B-tree reversing PK order (product_id first, store_id second) so R04 seeks
--       directly by product_id instead of probing store_inventory_pkey per store.
CREATE INDEX idx_store_inv_product_store
    ON store_inventory (product_id, store_id)
    INCLUDE (quantity_on_hand, selling_price);

-- Serves: R09, W04 (low-stock items at or below reorder_level for a store)
-- Type: Partial covering B-tree (quantity_on_hand <= reorder_level). Indexes only ~21% of rows
--       and pre-sorts by quantity_on_hand for R09.
CREATE INDEX idx_store_inv_low_stock
    ON store_inventory (store_id, quantity_on_hand)
    INCLUDE (product_id, reorder_level)
    WHERE quantity_on_hand <= reorder_level;

-- ---------------------------------------------------------------------
-- 4. customers
-- ---------------------------------------------------------------------

-- Serves: R25 (Mumbai customers filter: city_id = 2)
-- Type: Composite B-tree (city_id, customer_id) enabling Index Only Scan for city cohorts.
CREATE INDEX idx_customers_city
    ON customers (city_id, customer_id);

-- ---------------------------------------------------------------------
-- 5. riders
-- ---------------------------------------------------------------------

-- Serves: R21, W03 (active riders of a store, ordered by rider_id)
-- Type: Partial covering B-tree (status = 'ACTIVE'). Eliminates EXITED/ON_LEAVE riders and
--       provides min(rider_id) for W03 and full_name for R21 via Index Only Scan.
CREATE INDEX idx_riders_store_active
    ON riders (store_id, rider_id)
    INCLUDE (full_name)
    WHERE status = 'ACTIVE';

-- ---------------------------------------------------------------------
-- 6. orders
-- ---------------------------------------------------------------------

-- Serves: R06 (customer's latest order), R16 (customer cohort min(placed_at)), R25 (customer orders)
-- Type: Covering B-tree. Equality customer_id first, sort/range placed_at DESC second, timeline
--       and total_amount included for single-lookup Index Only Scan on R06 and zero-heap R16.
CREATE INDEX idx_orders_customer_placed
    ON orders (customer_id, placed_at DESC)
    INCLUDE (order_id, status, packed_at, picked_up_at, delivered_at, total_amount);

-- Serves: R07 (open orders screen at a store, sorted by placed_at)
-- Type: Partial covering B-tree on the ~0.07% non-terminal orders. Tiny footprint and near-zero
--       maintenance cost for historical DELIVERED/CANCELLED rows.
CREATE INDEX idx_orders_open_store_placed
    ON orders (store_id, placed_at)
    INCLUDE (order_id, status, rider_id)
    WHERE status IN ('PLACED', 'PACKING', 'OUT_FOR_DELIVERY');

-- Serves: W02 (most recent PLACED or PACKING order at store 43)
-- Type: Partial B-tree on store_id, order_id DESC where status IN ('PLACED', 'PACKING').
--       Satisfies max(order_id) in one index probe.
CREATE INDEX idx_orders_open_pack_store_id
    ON orders (store_id, order_id DESC)
    WHERE status IN ('PLACED', 'PACKING');

-- Serves: W03 (oldest PACKING order anywhere: min(order_id))
-- Type: Partial B-tree on order_id where status = 'PACKING'. Replaces 149k-row PK scan with 1 lookup.
CREATE INDEX idx_orders_packing_id
    ON orders (order_id)
    WHERE status = 'PACKING';

-- Serves: R22 (support console pagination), plus range scans R13, R15
-- Type: Covering B-tree (placed_at DESC, order_id DESC). Supports O(log N) keyset pagination
--       for R22 and Index Only Scans across June date windows without visiting the orders heap.
CREATE INDEX idx_orders_placed_desc
    ON orders (placed_at DESC, order_id DESC)
    INCLUDE (customer_id, store_id, status, total_amount);

-- Serves: R11 (store 43 June rider SLA), R15 (Bengaluru store hourly orders), R18 (store 43 June orders)
-- Type: Covering B-tree (store_id equality first, placed_at range second). Eliminates full orders
--       scans when filtering by store_id and placed_at window.
CREATE INDEX idx_orders_store_placed
    ON orders (store_id, placed_at)
    INCLUDE (order_id, status, rider_id, picked_up_at, delivered_at);

-- Serves: R21 (check whether an active rider had any order on 30 June 2026)
-- Type: Partial B-tree (rider_id, placed_at) where rider_id IS NOT NULL.
CREATE INDEX idx_orders_rider_placed
    ON orders (rider_id, placed_at)
    WHERE rider_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 7. order_items
-- ---------------------------------------------------------------------

-- Serves: R12 (co-purchased products for product 1236), R19 (category sales by product_id)
-- Type: Covering B-tree reversing order_items_pkey (product_id first, order_id second, quantity_delivered included).
--       Eliminates full 675k-row sequential scans when starting from product_id.
CREATE INDEX idx_order_items_product_order
    ON order_items (product_id, order_id)
    INCLUDE (quantity_delivered);

-- Serves: R13 (active products never used as substitutes in June 2026)
-- Type: Partial B-tree on (substitute_product_id, order_id) WHERE substitute_product_id IS NOT NULL.
--       Indexes only ~2.2% of rows (15,000 substitutions) with zero bloat for normal items.
CREATE INDEX idx_order_items_substitute
    ON order_items (substitute_product_id, order_id)
    WHERE substitute_product_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 8. inventory_movements
-- ---------------------------------------------------------------------

-- Serves: R10 (wastage per category in June 2026: EXPIRY / DAMAGE)
-- Type: Partial covering B-tree on ~11% wastage rows (moved_at range first, movement_type second).
CREATE INDEX idx_mov_wastage_moved
    ON inventory_movements (moved_at, movement_type)
    INCLUDE (product_id, quantity)
    WHERE movement_type IN ('EXPIRY', 'DAMAGE');

-- Serves: R24 (restocks per product at store 43 in last 7 days of June)
-- Type: Covering B-tree (store_id equality, movement_type equality, moved_at range).
CREATE INDEX idx_mov_store_type_moved
    ON inventory_movements (store_id, movement_type, moved_at)
    INCLUDE (product_id, quantity);

-- Serves: W05 (time-based retention pruning on append-only moved_at)
-- Type: BRIN index (pages_per_range = 32). Ultra-compact (~24 KB) with negligible insert/delete
--       overhead while pruning contiguous older page ranges when retention windows are selective.
CREATE INDEX idx_mov_moved_at_brin
    ON inventory_movements USING brin (moved_at)
    WITH (pages_per_range = 32);

-- ---------------------------------------------------------------------
-- 9. Materialized Views for Heavy Analytics Reports
--    (Allowed by Phase 4 brief for reporting workloads that do not
--    require sub-second live reads. Every MV carries a UNIQUE index so
--    it can be refreshed online via REFRESH MATERIALIZED VIEW CONCURRENTLY.)
-- ---------------------------------------------------------------------

-- Serves: R08 (monthly SLA late-delivery rate per store), R17 (monthly small-cart fees per store/city)
-- Grain: (month, store_id). Compresses 150k+ orders into ~2.1k monthly store buckets.
-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_monthly_store_order_metrics (hourly/nightly).
CREATE MATERIALIZED VIEW mv_monthly_store_order_metrics AS
SELECT date_trunc('month', placed_at) AS month,
       store_id,
       count(*) FILTER (WHERE status = 'DELIVERED') AS delivered_orders,
       count(*) FILTER (
           WHERE status = 'DELIVERED'
             AND delivered_at - placed_at > promised_minutes * interval '1 minute'
       ) AS late_deliveries,
       sum(small_cart_fee) AS small_cart_fees
FROM orders
GROUP BY 1, 2;

CREATE UNIQUE INDEX idx_mv_monthly_store_order_pk
    ON mv_monthly_store_order_metrics (month, store_id)
    INCLUDE (delivered_orders, late_deliveries, small_cart_fees);

-- Serves: R14 (monthly order-line fill / short-delivery rate per store)
-- Grain: (month, store_id). Pre-joins orders x order_items so R14 avoids scanning 675k+ order_items.
-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_monthly_store_fill_rate (hourly/nightly).
CREATE MATERIALIZED VIEW mv_monthly_store_fill_rate AS
SELECT date_trunc('month', o.placed_at) AS month,
       o.store_id,
       count(*) AS lines,
       count(*) FILTER (WHERE oi.quantity_delivered < oi.quantity_ordered) AS short_lines
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
GROUP BY 1, 2;

CREATE UNIQUE INDEX idx_mv_monthly_store_fill_rate_pk
    ON mv_monthly_store_fill_rate (month, store_id)
    INCLUDE (lines, short_lines);

-- Serves: R19 (monthly units sold per product for any category report)
-- Grain: (month, product_id). Covering unique index enables Index Only Scan when joined with products.
-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_monthly_product_sales (nightly).
CREATE MATERIALIZED VIEW mv_monthly_product_sales AS
SELECT date_trunc('month', o.placed_at) AS month,
       oi.product_id,
       sum(oi.quantity_delivered) AS units_sold
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY 1, 2;

CREATE UNIQUE INDEX idx_mv_monthly_product_sales_pk
    ON mv_monthly_product_sales (month, product_id)
    INCLUDE (units_sold);

-- Serves: R16 (monthly customer acquisition cohorts & retention cutoff counts)
-- Grain: (cohort, last_active_month). Reduces 150k+ orders / 40k+ customers to ~171 rows with zero
--        work_mem spill risk at 20x-100x scale while supporting any >= month-start activity threshold.
-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_cohort_last_activity (nightly).
CREATE MATERIALIZED VIEW mv_cohort_last_activity AS
WITH customer_bounds AS (
    SELECT customer_id,
           date_trunc('month', min(placed_at)) AS cohort,
           date_trunc('month', max(placed_at)) AS last_active_month
    FROM orders
    GROUP BY customer_id
)
SELECT cohort,
       last_active_month,
       count(*) AS customers
FROM customer_bounds
GROUP BY 1, 2;

CREATE UNIQUE INDEX idx_mv_cohort_last_activity_pk
    ON mv_cohort_last_activity (cohort, last_active_month)
    INCLUDE (customers);

-- Serves: R20 (daily delivered GMV and running totals across any date window)
-- Grain: (day). Covering unique index serves arbitrary date ranges via Index Only Scan.
-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_daily_delivered_gmv (hourly/nightly).
CREATE MATERIALIZED VIEW mv_daily_delivered_gmv AS
SELECT placed_at::date AS day,
       sum(total_amount) AS gmv
FROM orders
WHERE status = 'DELIVERED'
GROUP BY 1;

CREATE UNIQUE INDEX idx_mv_daily_delivered_gmv_pk
    ON mv_daily_delivered_gmv (day)
    INCLUDE (gmv);

-- Serves: R25 (top loyalty customers per city and year by delivered order count & spend)
-- Grain: (order_year, city_id, customer_id). Top-N covering index returns top 20 in O(log N).
-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_customer_yearly_delivered (nightly).
CREATE MATERIALIZED VIEW mv_customer_yearly_delivered AS
SELECT EXTRACT(YEAR FROM o.placed_at)::SMALLINT AS order_year,
       c.city_id,
       o.customer_id,
       count(*) AS orders,
       sum(o.total_amount) AS spend
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status = 'DELIVERED'
GROUP BY 1, 2, 3;

CREATE UNIQUE INDEX idx_mv_cust_yearly_deliv_pk
    ON mv_customer_yearly_delivered (order_year, city_id, customer_id);

CREATE INDEX idx_mv_cust_yearly_deliv_top
    ON mv_customer_yearly_delivered (order_year, city_id, orders DESC, spend DESC)
    INCLUDE (customer_id);

-- Refresh planner statistics and visibility maps so Index Only Scans avoid heap fetches
VACUUM ANALYZE;
