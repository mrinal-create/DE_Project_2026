# Phase 4: Query Optimization Report

- **Index definitions & Materialized Views:** [sql/05_indexes.sql](../sql/05_indexes.sql)  
- **Optimized SQL queries:** [sql/06_optimized_queries.sql](../sql/06_optimized_queries.sql)  
- **Benchmark command used:** `./benchmarks/run_benchmark.sh blinkit_db optimized 3 sql/06_optimized_queries.sql`  
- **Benchmark output files:** [optimized/summary.csv](../benchmarks/results/optimized/summary.csv) and `benchmarks/results/optimized/{R01..W05}.txt`

> **Quick Summary:**  
> Running all 30 queries originally took **4,012.9 ms** (~4 seconds). After adding smart indexes, materialized views, and query rewrites, the total runtime dropped to **37.2 ms**.  
> That is a **99.1% reduction in total time (107.8× faster overall)**.  
> Read queries sped up by **347×** (from 3,910.7 ms down to 11.3 ms), all query results stayed identical, and we fixed a hidden SQL `NULL` bug in `R13`.

---

## 1. Before vs. After Optimization Table (All 30 Queries)

Below is the comparison of all 30 queries before and after optimization.  
- **Improvement %** = `(Before - After) / Before × 100`  
- Every query returns the exact same data as before (same rows, same columns, same order where `ORDER BY` is used).

| Query | Before (ms) | What was slow in the original query? | How we fixed it | After (ms) | Improvement | Same result? |
|---|---:|---|---|---:|---:|:---:|
| **R01** | 0.095 | Scanned all stores in the table one by one. | Added a partial index `idx_dark_stores_active_coords` on active stores only. | 0.139 | −46.3% (0.7×) | ✅ |
| **R02** | 0.446 | Scanned products and did 125 single-row lookups plus sorting in memory. | Added index `idx_store_inv_instock_store_price` pre-sorted by price for in-stock items. | 0.303 | 32.1% (1.5×) | ✅ |
| **R03** | 1.235 | Searched product names with `ILIKE '%milk%'` by reading every product row. | Added a GIN trigram index (`pg_trgm`) to make text search instant. | 0.318 | 74.3% (3.9×) | ✅ |
| **R04** | 0.197 | Primary key starts with `store_id`, so looking up by `product_id` required scanning. | Added index `idx_store_inv_product_store` starting with `product_id`. | 0.110 | 44.2% (1.8×) | ✅ |
| **R05** | 0.063 | Already fast (looked up 4 items using primary key). | Used covering index to answer the query entirely inside the index. | 0.090 | −42.9% (0.7×) | ✅ |
| **R06** | 8.001 | Read all 150,000 orders to find the newest order for 1 customer. | Added covering index `idx_orders_customer_placed (customer_id, placed_at DESC)`. | 0.077 | 99.0% (103.9×) | ✅ |
| **R07** | 10.876 | Read all 150,000 orders across parallel CPU workers to find live orders. | Added partial index `idx_orders_open_store_placed` indexing only open orders (~0.07% of table). | 0.067 | 99.4% (162.3×) | ✅ |
| **R08** | 11.796 | Scanned 142,000+ orders to calculate delivery delay percentages per store. | Stored monthly store SLA metrics in Materialized View `mv_monthly_store_order_metrics`. | 0.174 | 98.5% (67.8×) | ✅ |
| **R09** | 0.531 | Read all 1,050 inventory rows for a store and threw away 821 rows with enough stock. | Added partial index `idx_store_inv_low_stock` containing only low-stock items. | 0.351 | 33.9% (1.5×) | ✅ |
| **R10** | 9.363 | Scanned 90,000 inventory movement rows to find waste (damage and expired items). | Added partial index `idx_mov_wastage_moved` indexing only damage/expiry movements. | 0.715 | 92.4% (13.1×) | ✅ |
| **R11** | 10.902 | Scanned all 150,000 orders to calculate rider delivery times for store 43 in June. | Added covering index `idx_orders_store_placed (store_id, placed_at)`. | 0.136 | 98.8% (80.2×) | ✅ |
| **R12** | 14.668 | Scanned all 675,000 order items to find products bought together with item 1236. | Added covering index `idx_order_items_product_order (product_id, order_id)`. | 1.976 | 86.5% (7.4×) | ✅ |
| **R13** | 34.488 | Read products, items, and orders. **Returned 0 rows due to a SQL NULL bug in `NOT IN`.** | Rewrote `NOT IN` to `NOT EXISTS` + added index on substitute products. | 3.999 | 88.4% (8.6×) | Fixed (`0` → `1,250` rows) |
| **R14** | 32.423 | Scanned 150k orders and 675k order items to compute line fill rate. | Pre-aggregated monthly fill rates in Materialized View `mv_monthly_store_fill_rate`. | 0.165 | 99.5% (196.5×) | ✅ |
| **R15** | 15.151 | Function `DATE(placed_at)` prevented Postgres from using any regular index. | Rewrote date filter to sargable range `>= '2026-06-29' AND < '2026-06-30'`. | 0.177 | 98.8% (85.6×) | ✅ |
| **R16** | 57.639 | Scanned all 150,000 orders twice to build customer cohorts and check June activity. | Stored cohort summaries in Materialized View `mv_cohort_last_activity` (only 171 rows). | 0.107 | 99.8% (538.7×) | ✅ |
| **R17** | 59.375 | `EXTRACT(YEAR FROM placed_at)` forced a full table scan and a 50,000-row sort. | Read monthly small-cart fee sums directly from `mv_monthly_store_order_metrics`. | 0.446 | 99.2% (133.1×) | ✅ |
| **R18** | 10.614 | Scanned the full orders table to check store 43 June inventory sales. | Used index `idx_orders_store_placed` to jump straight to store 43's June orders. | 1.037 | 90.2% (10.2×) | ✅ |
| **R19** | 3509.217 | Ran a subquery that scanned all 675,000 order items **125 separate times** (~3.5 seconds). | Pre-aggregated monthly product sales in `mv_monthly_product_sales` and joined with products. | 0.374 | 100.0% (9,382.9×) | ✅ |
| **R20** | 17.223 | Cast `placed_at::date` forced a full scan of 150,000 orders to sum daily revenue. | Read daily totals directly from Materialized View `mv_daily_delivered_gmv`. | 0.096 | 99.4% (179.4×) | ✅ |
| **R21** | 9.462 | Scanned all riders and all orders to find active riders who had no orders on June 30. | Added partial indexes on active riders and non-null order riders. | 0.078 | 99.2% (121.3×) | ✅ |
| **R22** | 65.379 | Scanned all 150,000 orders and dumped 7.3 MB to disk just to skip `OFFSET 100000`. | Replaced `OFFSET` with keyset cursor `(placed_at, order_id) < last_seen_value`. | 0.093 | 99.9% (703.0×) | ✅ |
| **R23** | 0.042 | Already fast (looked up product by unique SKU code). | Kept original unique index on `products(sku)`. | 0.039 | 7.1% (1.1×) | ✅ |
| **R24** | 5.094 | Scanned 90,000 inventory movements to find restocks for store 43 in late June. | Added covering index `idx_mov_store_type_moved (store_id, movement_type, moved_at)`. | 0.123 | 97.6% (41.4×) | ✅ |
| **R25** | 26.449 | Joined and scanned 33,000 customers and 150,000 orders to find top 20 loyal shoppers. | Pre-aggregated annual customer spend in `mv_customer_yearly_delivered` with Top-N index. | 0.075 | 99.7% (352.7×) | ✅ |
| **W01** | 1.109 | Inserts a single order row. | Unchanged query. Pays a tiny update cost for 7 indexes on `orders` (+0.3 ms). | 1.413 | −27.4% (0.8×) | ✅ |
| **W02** | 19.534 | Scanned 150,000 orders to find the newest unfulfilled order for store 43. | Partial index `idx_orders_open_pack_store_id` finds the order in 1 step. | 0.422 | 97.8% (46.3×) | ✅ |
| **W03** | 22.797 | Walked through almost all 150,000 orders to find the oldest order being packed. | Partial index `idx_orders_packing_id` jumps directly to the oldest packing order. | 0.612 | 97.3% (37.2×) | ✅ |
| **W04** | 1.236 | Updates 229 low-stock inventory items for store 43. | Uses index `idx_store_inv_low_stock` to locate rows; updating index entries adds ~1 ms. | 2.394 | −93.7% (0.5×) | ✅ |
| **W05** | 57.514 | Deleted 60,165 old records from `inventory_movements` by scanning the whole table. | Added a compact BRIN index on `moved_at` to skip irrelevant blocks. | 21.130 | 63.3% (2.7×) | ✅ |
| **Total** | **4,012.919** | | | **37.236** | **99.1% (107.8×)** | |

---

## 2. The Buggy Query Found & Fixed (`R13`)

### Why did the original `R13` return 0 rows?
The original query was written like this:
```sql
SELECT p.product_id, p.product_name
FROM products p
WHERE p.is_active
  AND p.product_id NOT IN (
      SELECT oi.substitute_product_id
      FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
      WHERE o.placed_at >= '2026-06-01' AND o.placed_at < '2026-07-01'
  );
```

In the `order_items` table, most items are delivered without substitution, so **`substitute_product_id` is `NULL` on 660,000 out of 675,000 rows** (~98% of the rows).

In SQL:
- Comparing any value to `NULL` (such as `product_id <> NULL`) does not return `TRUE` or `FALSE`—it returns `UNKNOWN`.
- When you use `NOT IN (val1, val2, NULL)`, SQL checks if `product_id <> val1 AND product_id <> val2 AND product_id <> NULL`.
- Because one comparison is `UNKNOWN`, the whole `AND` condition can never be `TRUE`.
- As a result, the query rejected every single product and returned **0 rows**!

### The Fix
We rewrote the query using `NOT EXISTS`:
```sql
SELECT p.product_id, p.product_name
FROM products p
WHERE p.is_active
  AND NOT EXISTS (
      SELECT 1
      FROM order_items oi
      JOIN orders o ON o.order_id = oi.order_id
      WHERE oi.substitute_product_id = p.product_id
        AND o.placed_at >= '2026-06-01' AND o.placed_at < '2026-07-01'
  );
```
`NOT EXISTS` checks if a matching record exists. It is completely safe with `NULL`s because it looks for matched rows rather than evaluating inequality chains.
- **Before:** `0` rows (took `34.5 ms`)
- **After:** **`1,250` rows** (took `4.0 ms`) — exactly the 1,463 active products minus the 213 products that were actually used as substitutes in June.

---

## 3. How We Proved Results Did Not Change

To be 100% certain our rewritten queries produced the exact same results as the originals, we ran a symmetric difference test (`EXCEPT ALL`) on both:

```sql
-- This query returns rows that exist in one version but not the other.
-- If the result is 0 rows, both queries return identical data!
(SELECT * FROM original EXCEPT ALL SELECT * FROM rewritten)
UNION ALL
(SELECT * FROM rewritten EXCEPT ALL SELECT * FROM original);
```

### Verification Results

| Query | Rewrite Description | Original Rows | Rewritten Rows | Row Difference |
|---|---|---:|---:|:---:|
| `R08` | Direct orders scan → Materialized View (`mv_monthly_store_order_metrics`) | 118 | 118 | **0** |
| `R14` | 675k order-items scan → Materialized View (`mv_monthly_store_fill_rate`) | 118 | 118 | **0** |
| `R15` | `DATE(placed_at) = '2026-06-29'` → Sargable range `>= '2026-06-29' AND < '2026-06-30'` | 36 | 36 | **0** |
| `R16` | Double scan of 150k orders → Materialized View (`mv_cohort_last_activity`) | 18 | 18 | **0** |
| `R17` | `EXTRACT(YEAR FROM ...)` scan → Materialized View joined with `dark_stores` | 60 | 60 | **0** |
| `R19` | 125 repeated subquery scans → `LEFT JOIN` on `mv_monthly_product_sales` | 125 | 125 | **0** |
| `R20` | Date cast scan → Materialized View (`mv_daily_delivered_gmv`) | 30 | 30 | **0** |
| `R22` | `OFFSET 100000 LIMIT 25` → Keyset cursor `(placed_at, order_id) < (...)` | 25 | 25 | **0** (exact same order) |
| `R25` | Joined scan of customers and orders → Materialized View (`mv_customer_yearly_delivered`) | 20 | 20 | **0** (exact same order) |

*(Note: All real-time customer and store queries—`R01` to `R07`, `R09` to `R13`, `R15`, `R18`, `R21` to `R24`, and all write queries `W01` to `W05`—continue to read and write directly against live base tables.)*

### Materialized View Refresh Strategy
Materialized views are summaries of historical data. To ensure reports don't show stale numbers and never block live application traffic, every view has a `UNIQUE INDEX` and is refreshed concurrently in the background:
- **Hourly Refresh (Scheduled via background worker / `pg_cron`):**
  - `REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_monthly_store_order_metrics;` (`R08`, `R17`)
  - `REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_monthly_store_fill_rate;` (`R14`)
  - `REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_daily_delivered_gmv;` (`R20`)
- **Nightly Refresh (Runs daily at 02:00 AM IST):**
  - `REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_monthly_product_sales;` (`R19`)
  - `REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_cohort_last_activity;` (`R16`)
  - `REFRESH MATERIALIZED VIEW CONCURRENTLY blinkit.mv_customer_yearly_delivered;` (`R25`)

---

## 4. Top 5 Query Improvements (Before & After Plans)

### 4.1 `R19` (Product Sales in Fruits & Vegetables)
- **Time:** `3,509.2 ms` → `0.37 ms` (**9,382× faster**)
- **The problem:** The original query ran an unindexed subquery inside the `SELECT` clause. Because there are 125 products in that category, Postgres had to scan all 675,000 order items 125 times (reading over 767,000 memory pages).
- **The fix:** We pre-calculated monthly product sales in a summary view (`mv_monthly_product_sales`) and used a `LEFT JOIN`.
- **Plan comparison:**
  - *Before:* `Seq Scan on order_items` executed 125 times (`actual time=26.788 ms loops=125`, Total runtime: `3,505.8 ms`).
  - *After:* `Index Only Scan` on `idx_mv_monthly_product_sales_pk` reading just 18 memory pages (`actual time=0.063..0.162 ms`, Total runtime: `0.38 ms`).

### 4.2 `R22` (Support Console Page 4,001)
- **Time:** `65.4 ms` → `0.09 ms` (**703× faster**)
- **The problem:** To skip the first 100,000 rows (`OFFSET 100000`), Postgres had to scan all 150,000 orders, sort them all in memory, write 7.3 MB of temporary data to disk, and throw away the first 100,000 rows.
- **The fix:** Keyset pagination (cursor). Instead of counting 100,000 rows, the query asks directly for rows after the last row seen on page 4,000: `WHERE (placed_at, order_id) < ('2025-07-02 00:00:00+05:30', 50001)`.
- **Plan comparison:**
  - *Before:* Full `Seq Scan on orders` + `Sort Method: external merge Disk: 7352kB` (`65.3 ms`).
  - *After:* `Index Only Scan` using `idx_orders_placed_desc` reading only 4 pages (`0.10 ms`).

### 4.3 `R17` (Small-Cart Fees by City for 2026)
- **Time:** `59.4 ms` → `0.45 ms` (**133× faster**)
- **The problem:** `EXTRACT(YEAR FROM placed_at) = 2026` prevented index usage, forcing a full scan of 150,000 orders and sorting 49,725 rows.
- **The fix:** Read pre-aggregated monthly fee sums from `mv_monthly_store_order_metrics` and joined with dark stores.
- **Plan comparison:**
  - *Before:* `Seq Scan on orders` (100,275 rows thrown away) + large sort (`58.9 ms`).
  - *After:* `Index Only Scan` reading 708 rows from the materialized view in 16 buffer hits (`0.47 ms`).

### 4.4 `R16` (Monthly Customer Cohorts & Retention)
- **Time:** `57.6 ms` → `0.11 ms` (**538× faster**)
- **The problem:** The query scanned the 150,000 orders table twice—once to find each customer's first order month, and once more for every customer to see if they placed an order in June.
- **The fix:** Stored each customer's first and last active months in `mv_cohort_last_activity` (compressing 150,000 orders down to just 171 summary rows).
- **Plan comparison:**
  - *Before:* Two full table scans of `orders` + hash aggregation on 39,011 rows (`58.0 ms`).
  - *After:* Quick scan of just 171 rows in `mv_cohort_last_activity` (`0.11 ms`).

### 4.5 `R14` (Order Line Short-Delivery Fill Rate)
- **Time:** `32.4 ms` → `0.17 ms` (**196× faster**)
- **The problem:** Joined all 150,000 orders to all 675,000 order items across 3 parallel CPU workers.
- **The fix:** Pre-aggregated monthly store lines and short lines in `mv_monthly_store_fill_rate`.
- **Plan comparison:**
  - *Before:* `Parallel Seq Scan` on both `order_items` and `orders` reading 6,641 pages (`32.7 ms`).
  - *After:* `Index Only Scan` on `idx_mv_monthly_store_fill_rate_pk` reading just 6 pages (`0.18 ms`).

---

## 5. Write Overhead Analysis (`W01` to `W05`)

Indexes make reading data nearly instantaneous, but whenever a table is modified (`INSERT`, `UPDATE`, `DELETE`), Postgres must also update the indexes on that table. Below is how our write queries were affected:

| Write Query | Before (ms) | After (ms) | Difference | Is this acceptable? |
|---|---:|---:|---:|---|
| **`W01`** (`INSERT` order) | 1.109 | 1.413 | **+0.304 ms (+27%)** | **Yes.** Updating 7 indexes on `orders` added 0.3 ms. At **1.4 ms**, checkout is still well below the 5 ms target. |
| **`W02`** (`UPDATE` inventory for latest order) | 19.534 | 0.422 | **−19.112 ms (−98%)** | **46× faster.** The original query spent 19 ms scanning all orders to find the newest order. Our partial index found it instantly, easily saving far more time than the small update cost. |
| **`W03`** (`UPDATE` order dispatch to rider) | 22.797 | 0.612 | **−22.185 ms (−97%)** | **37× faster.** Partial index `idx_orders_packing_id` jumps directly to the oldest order being packed instead of checking 149,000 records. |
| **`W04`** (`UPDATE` inventory low-stock replenishment) | 1.236 | 2.394 | **+1.158 ms (+94%)** | **Yes.** Updating 229 low-stock items updates 2 indexes. At **2.4 ms**, this is perfectly fine for a background restocking job. |
| **`W05`** (`DELETE` old movements before 2026) | 57.514 | 21.130 | **−36.384 ms (−63%)** | **2.7× faster.** BRIN index skips blocks that don't match. In Phase 5, monthly partitioning makes this instant (< 5 ms) by simply dropping old tables. |

---

## 6. Index & Storage Report (`pg_relation_size`)

- Total database size on disk: **201 MB**
  - 10 Base Tables: **68 MB**
  - Indexes: **118 MB** (37 table indexes = 112 MB; 7 materialized view indexes = 6 MB)
  - Materialized Views: **5 MB**

### Storage Breakdown by Table and Index

| Table or Materialized View | Table Size | Index Name | Index Size | Size vs Table | Why we need this index |
|---|---:|---|---:|---:|---|
| `order_items` | 34 MB | `idx_order_items_product_order` | 26 MB | 76.5% | Allows looking up order items by `product_id` (`R12`) |
| `order_items` | 34 MB | `order_items_pkey` (Primary Key) | 20 MB | 58.8% | Lookups by `(order_id, product_id)` |
| `order_items` | 34 MB | `idx_order_items_substitute` | 480 kB | 1.4% | Partial index on substituted items only (`R13`) |
| `orders` | 18 MB | `idx_orders_customer_placed` | 14 MB | 77.8% | Customer order history without touching the table (`R06`) |
| `orders` | 18 MB | `idx_orders_store_placed` | 11 MB | 61.1% | Store orders filtered by date (`R11`, `R18`) |
| `orders` | 18 MB | `idx_orders_placed_desc` | 8,624 kB | 46.8% | Instant pagination and date scans (`R15`, `R22`) |
| `orders` | 18 MB | `idx_orders_rider_placed` | 4,464 kB | 24.2% | Tracks orders assigned to riders (`R21`) |
| `orders` | 18 MB | `orders_pkey` (Primary Key) | 3,312 kB | 18.0% | Primary key lookup by `order_id` |
| `orders` | 18 MB | `idx_orders_open_store_placed` | 16 kB | 0.1% | Tiny partial index for active/open orders (`R07`) |
| `orders` | 18 MB | `idx_orders_open_pack_store_id` | 16 kB | 0.1% | Finds latest unfulfilled order in 1 step (`W02`) |
| `orders` | 18 MB | `idx_orders_packing_id` | 16 kB | 0.1% | Finds oldest packing order in 1 step (`W03`) |
| `store_inventory` | 7,496 kB | `idx_store_inv_product_store` | 5,008 kB | 66.8% | Reverse lookup by `product_id` (`R04`, `R05`) |
| `store_inventory` | 7,496 kB | `idx_store_inv_instock_store_price` | 4,768 kB | 63.6% | In-stock store items pre-sorted by price (`R02`, `R03`) |
| `store_inventory` | 7,496 kB | `store_inventory_pkey` (Primary Key) | 2,800 kB | 37.4% | Store inventory primary key `(store_id, product_id)` |
| `store_inventory` | 7,496 kB | `idx_store_inv_low_stock` | 760 kB | 10.1% | Partial index for low-stock alerts (`R09`, `W04`) |
| `inventory_movements` | 6,000 kB | `idx_mov_store_type_moved` | 4,392 kB | 73.2% | Store restocks filtered by date (`R24`) |
| `inventory_movements` | 6,000 kB | `inventory_movements_pkey` | 1,984 kB | 33.1% | Primary key on `movement_id` |
| `inventory_movements` | 6,000 kB | `idx_mov_wastage_moved` | 424 kB | 7.1% | Partial index on damage and expiry only (`R10`) |
| `inventory_movements` | 6,000 kB | `idx_mov_moved_at_brin` | 24 kB | 0.4% | Super-compact BRIN index for date pruning (`W05`) |
| `customers` | 3,272 kB | Primary Key + Unique Indexes | 3,584 kB | 109.5% | ID, Email, and Phone unique lookups |
| `customers` | 3,272 kB | `idx_customers_city` | 896 kB | 27.4% | Customer lookup by city |
| `products` | 152 kB | `idx_products_name_trgm` / `category_cover` | 216 kB | 142.1% | Trigram search (`R03`) and category lookup (`R02`) |
| `riders` | 136 kB | `idx_riders_store_active` | 80 kB | 58.8% | Active riders per store (`R21`, `W03`) |
| `dark_stores` | 16 kB | `idx_dark_stores_active_coords` | 16 kB | 100.0% | Active dark store coordinates (`R01`) |
| `mv_customer_yearly_delivered` *(MV)* | 3,272 kB | `idx_mv_cust_yearly_deliv_top` + `_pk` | 4,560 kB | 139.4% | Top loyalty customer lookups (`R25`) |
| `mv_monthly_product_sales` *(MV)* | 1,376 kB | `idx_mv_monthly_product_sales_pk` | 1,080 kB | 78.5% | Fast product sales report (`R19`) |
| `mv_monthly_store_order_metrics` *(MV)* | 144 kB | `idx_mv_monthly_store_order_pk` | 144 kB | 100.0% | SLA and fee report (`R08`, `R17`) |
| `mv_monthly_store_fill_rate` *(MV)* | 128 kB | `idx_mv_monthly_store_fill_rate_pk` | 120 kB | 93.8% | Store fill rate report (`R14`) |
| `mv_daily_delivered_gmv` *(MV)* | 24 kB | `idx_mv_daily_delivered_gmv_pk` | 40 kB | 166.7% | Daily GMV report (`R20`) |
| `mv_cohort_last_activity` *(MV)* | 16 kB | `idx_mv_cohort_last_activity_pk` | 16 kB | 100.0% | Customer cohort report (`R16`) |

---

## 7. Queries We Could Not Speed Up Further (and Why)

1. **`W05` (`57.5 ms` → `21.1 ms`, `2.7× faster`):**  
   This query deletes **60,165 records** (67% of the entire `inventory_movements` table). Even with a fast BRIN index finding the right data pages, Postgres still has to physically remove 60,000 rows from disk and clean up entries in 3 indexes. In Phase 5, we solve this with **table partitioning** so old months can be detached instantly without deleting rows one by one.
2. **`R13` (`34.5 ms` → `4.0 ms`, `8.6× faster`):**  
   We kept this as a live database query rather than a summary view because store managers need live updates. It takes 4 ms because it has to cross-reference 15,000 substitutions against June's 8,241 orders. At 4 ms, it easily beats the 250 ms target.
3. **`R12` (`14.7 ms` → `2.0 ms`, `7.4× faster`):**  
   Must stay live against real-time cart data. It performs 466 lookups on the order-items index to count which items are frequently bought together. 2 ms is well within interactive limits.
4. **`R01`, `R05`, `R23` (`0.04 ms – 0.14 ms`) & `W01`, `W04` (`1.4 ms – 2.4 ms`):**  
   These queries are already as fast as computer hardware allows. Point lookups take less than 0.15 milliseconds, and single-row order writes take 1.4 milliseconds while keeping all read indexes up to date.
