# Phase 3: Baseline Query Timings

**Database:** `blinkit_db` (schema `blinkit`, constraints & auto PK/UNIQUE indexes only — no tuning indexes)  
**Engine:** PostgreSQL 18.6 (Postgres.app) on Apple MacBook Pro  
**Method:** `./benchmarks/run_benchmark.sh blinkit_db baseline` (`EXPLAIN (ANALYZE, BUFFERS)`, 3 runs per query, writes wrapped in `BEGIN ... ROLLBACK`).  
**Raw artifacts:** [summary.csv](../benchmarks/results/baseline/summary.csv) and `benchmarks/results/baseline/{R01..W05}.txt`.

---

## 1. Baseline Timing Table (All 30 Queries)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Store assignment: the nearest active dark store within ~3 km of a customer at (12.93, 77.62) | READ | 0.097 | 0.098 | 0.090 | 0.095 |
| R02: Category page: Dairy products in stock at store 43, cheapest first | READ | 0.442 | 0.444 | 0.451 | 0.446 |
| R03: Search: products with "milk" in the name that are in stock at store 43 | READ | 1.280 | 1.214 | 1.210 | 1.235 |
| R04: Product page: stock of product 1236 in every Bengaluru dark store | READ | 0.193 | 0.204 | 0.194 | 0.197 |
| R05: Cart check: current stock and price of 4 cart items at store 43 | READ | 0.064 | 0.063 | 0.062 | 0.063 |
| R06: Order tracking: customer 1027's latest order with its timeline | READ | 7.986 | 8.052 | 7.966 | 8.001 |
| R07: Store screen: open orders at store 43 (not yet delivered or cancelled) | READ | 10.901 | 10.772 | 10.956 | 10.876 |
| R08: SLA report: share of June 2026 deliveries that took longer than promised, per store | READ | 11.797 | 11.871 | 11.721 | 11.796 |
| R09: Replenishment: products at store 43 at or below their reorder level | READ | 0.527 | 0.499 | 0.567 | 0.531 |
| R10: Wastage: units lost to expiry or damage per category in June 2026 | READ | 9.392 | 9.477 | 9.219 | 9.363 |
| R11: Rider performance: average minutes from pickup to delivery per rider at store 43 (June 2026) | READ | 10.814 | 11.041 | 10.851 | 10.902 |
| R12: Recommendations: products most often bought together with product 1236 | READ | 14.725 | 14.581 | 14.697 | 14.668 |
| R13: Category team: active products that were never given as a substitute in June 2026 | READ | 34.378 | 34.697 | 34.390 | 34.488 |
| R14: Fill rate: share of order lines delivered short, per store, June 2026 | READ | 32.753 | 32.558 | 31.957 | 32.423 |
| R15: Staffing: orders per hour at Bengaluru stores on 29 June 2026 | READ | 15.079 | 15.146 | 15.229 | 15.151 |
| R16: Growth: monthly cohorts—customers by month of first order, and how many ordered again in June 2026 | READ | 58.023 | 57.358 | 57.537 | 57.639 |
| R17: Finance: small-cart fee collected per city per month in 2026 | READ | 58.964 | 58.995 | 60.166 | 59.375 |
| R18: Dead stock: products in stock at store 43 that did not sell there in June 2026 | READ | 11.224 | 10.316 | 10.302 | 10.614 |
| R19: Category report: June 2026 units sold of every Fruits & Vegetables product | READ | 3505.836 | 3513.091 | 3508.724 | 3509.217 |
| R20: Finance: daily GMV and running total for June 2026 | READ | 16.991 | 17.221 | 17.458 | 17.223 |
| R21: Store manager: active riders of store 43 with no delivery on 30 June 2026 | READ | 9.303 | 9.580 | 9.504 | 9.462 |
| R22: Support console: all orders, newest first, page 4,001 (25 per page) | READ | 65.260 | 63.970 | 66.906 | 65.379 |
| R23: Warehouse scanner: look up a product by SKU | READ | 0.044 | 0.041 | 0.041 | 0.042 |
| R24: Supply chain: units restocked per product at store 43 in the last 7 days of June 2026 | READ | 5.051 | 5.119 | 5.111 | 5.094 |
| R25: Loyalty: 20 Mumbai customers with the most delivered orders in 2026 | READ | 26.626 | 26.521 | 26.200 | 26.449 |
| W01: Checkout: place a new order at store 43 | WRITE | 1.186 | 1.051 | 1.089 | 1.109 |
| W02: Packing done: reduce store 43's stock for every line of its most recent PLACED or PACKING order | WRITE | 19.365 | 19.419 | 19.818 | 19.534 |
| W03: Dispatch: give the oldest PACKING order (anywhere) to its store's first active rider | WRITE | 22.780 | 22.651 | 22.961 | 22.797 |
| W04: Nightly replenishment at store 43: top up everything at or below reorder level | WRITE | 1.213 | 1.447 | 1.048 | 1.236 |
| W05: Data retention: delete inventory movements older than 1 January 2026 | WRITE | 66.204 | 58.020 | 48.317 | 57.514 |
| **Total (sum of all 30)** | | **4018.498** | **4015.517** | **4004.742** | **4012.919** |

---

## 2. Scan Types & Plan Diagnosis (Per Query)

- **R01 (`0.095 ms`):** `Seq Scan on dark_stores` + `Sort`. Fast only because `dark_stores` currently has 120 rows; without an active geo index it discards 119 rows.
- **R02 (`0.446 ms`):** `Seq Scan on products` + `Seq Scan on categories` + `Index Scan using store_inventory_pkey on store_inventory` + `Sort`. Fast at seed size via `store_inventory_pkey(store_id, product_id)`, but performs 125 PK probes and sorts in memory instead of scanning pre-filtered inventory.
- **R03 (`1.235 ms`):** `Seq Scan on products` + `Index Scan using store_inventory_pkey` + `Sort`. Slow relative to PK lookup because `ILIKE '%milk%'` scans all 1,500 `products` rows (`1,469` discarded) without a trigram index.
- **R04 (`0.197 ms`):** `Seq Scan on dark_stores` + `Index Scan using store_inventory_pkey` + `Sort`. Probe order works for 19 Bengaluru stores, but `store_inventory_pkey` has `store_id` first, forcing 19 random lookups instead of a single lookup on `product_id`.
- **R05 (`0.063 ms`):** `Index Scan using store_inventory_pkey on store_inventory`. Already optimal (`Index Cond: store_id = 43 AND product_id = ANY(...)`) with 4 index searches.
- **R06 (`8.001 ms`):** `Seq Scan on orders` + `Sort (top-N heapsort)`. Slow for a real-time customer lookup because no index exists on `orders(customer_id, placed_at)`, forcing a full scan of 150,000 orders (`149,991` discarded).
- **R07 (`10.876 ms`):** `Parallel Seq Scan on orders` + `Sort`. Scans all 150,000 orders across 2 workers just to return 2 open orders at store 43 because no `(store_id, status)` / partial open-order index exists.
- **R08 (`11.796 ms`):** `Parallel Seq Scan on orders` + `Partial HashAggregate` + `Sort` + `Finalize GroupAggregate`. Scans all 150,000 `orders` rows (`142,185` discarded across workers) because `placed_at` and `status` are unindexed.
- **R09 (`0.531 ms`):** `Bitmap Index Scan` + `Bitmap Heap Scan on store_inventory` (via `store_inventory_pkey` on `store_id = 43`) + `Hash Join` with `Seq Scan on products` + `Sort`. Reads all 1,050 SKUs of store 43 and discards `821` above reorder level.
- **R10 (`9.363 ms`):** `Seq Scan on inventory_movements` + `Hash Join` (`Seq Scan on products`) + `Index Scan using categories_pkey` + `HashAggregate` + `Sort`. Scans all 90,000 movements (`89,430` discarded) because `moved_at` / `movement_type` are unindexed.
- **R11 (`10.902 ms`):** `Parallel Seq Scan on orders` + `Sort` + `GroupAggregate`. Scans all 150,000 orders to isolate ~69 June delivered orders at store 43 (`149,931` rows discarded).
- **R12 (`14.668 ms`):** `Parallel Seq Scan on order_items a` + `Nested Loop` -> `Index Only Scan using order_items_pkey on order_items b` + `Sort` + `GroupAggregate` + `Limit`. Scans all 675,000 rows of `order_items` to find 466 lines containing `product_id = 1236` because `(order_id, product_id)` cannot seek by `product_id`.
- **R13 (`34.488 ms`):** `Seq Scan on products` + `SubPlan 1` (`Parallel Hash Join` of `Parallel Seq Scan on order_items` and `Parallel Seq Scan on orders`). Scans all 675k order items and 150k orders, **and returns 0 rows (wrong answer!)** because `substitute_product_id` contains `NULL`s inside `NOT IN`.
- **R14 (`32.423 ms`):** `Parallel Hash Join` (`Parallel Seq Scan on order_items` + `Parallel Seq Scan on orders`) + `Partial HashAggregate` + `Finalize GroupAggregate` + `Sort`. Full sequential scans of both `orders` (150k) and `order_items` (675k) because `orders(placed_at)` is unindexed.
- **R15 (`15.151 ms`):** `Seq Scan on orders` + `Nested Loop` -> `Index Scan using dark_stores_pkey` + `Sort` + `GroupAggregate`. Uses non-sargable `DATE(o.placed_at) = '2026-06-29'`, forcing a full 150,000-row scan of `orders` (`149,725` discarded).
- **R16 (`57.639 ms`):** `Seq Scan on orders` (`HashAggregate` for `firsts`) + `SubPlan 2` (`Seq Scan on orders o`) + `Sort` + `GroupAggregate`. Reads the entire 150k-row `orders` table **twice** plus builds and sorts 39,011 customer groups.
- **R17 (`59.375 ms`):** `Seq Scan on orders` + `Index Scan using dark_stores_pkey` + `Sort` + `GroupAggregate`. Uses non-sargable `EXTRACT(YEAR FROM o.placed_at) = 2026`, scanning all 150k orders (`100,275` discarded) and sorting 49,725 tuples.
- **R18 (`10.614 ms`):** `Seq Scan on orders` + `Index Only Scan using order_items_pkey` + `Hash Right Anti Join` with `Bitmap Heap Scan on store_inventory` + `Hash Join` (`Seq Scan on products`). Scans all 150,000 orders (`149,926` discarded) just to get store 43's 74 June orders.
- **R19 (`3509.217 ms`):** `Seq Scan on categories` + `Seq Scan on products` + **correlated `SubPlan 1` executed 125 times**, each doing a full **`Seq Scan on order_items` (675,000 rows)** + 56,292 `Index Scan using orders_pkey`. Accounted for **87.5% of total baseline workload time** due to `O(125 × 675,000)` nested scans!
- **R20 (`17.223 ms`):** `Parallel Seq Scan on orders` + `Sort` + `GroupAggregate` + `WindowAgg`. Non-sargable `placed_at::date BETWEEN ...` forces a full scan of 150,000 orders (`142,185` discarded).
- **R21 (`9.462 ms`):** `Seq Scan on riders` + `Seq Scan on orders` + `Hash Right Anti Join` + `Sort`. Scans all 150,000 orders (`149,726` discarded) and all 1,800 riders (`1,786` discarded) due to missing `(store_id, status)` and `(rider_id, placed_at)` indexes.
- **R22 (`65.379 ms`):** `Seq Scan on orders` + `Sort (external merge Disk: 7352kB)` + `Limit`. Reads and disk-sorts all 150,000 orders only to discard the first 100,000 rows (`OFFSET 100000`).
- **R23 (`0.042 ms`):** `Index Scan using uq_products_sku on products`. Already optimal (`0.042 ms`) thanks to the automatic `UNIQUE` B-tree index on `products(sku)`.
- **R24 (`5.094 ms`):** `Seq Scan on inventory_movements` + `Sort` + `GroupAggregate`. Scans all 90,000 movement rows (`89,993` discarded) to find just 7 matching restock rows for store 43.
- **R25 (`26.449 ms`):** `Hash Join` (`Seq Scan on orders` + `Seq Scan on customers`) + `HashAggregate` + `Sort (top-N heapsort)`. Full scans of 40,000 customers (`33,600` discarded) and 150,000 orders (`102,275` discarded).
- **W01 (`1.109 ms`):** `Insert on orders`. Fast single-row insert validating PK + FK constraints (`customers`, `dark_stores`).
- **W02 (`19.534 ms`):** `InitPlan 1` (`Seq Scan on orders` discarding 149,998 rows!) + `Index Scan using order_items_pkey` + `Index Scan using store_inventory_pkey` + `Update on store_inventory`. Almost all 19.5 ms is wasted scanning 150k orders to find `max(order_id)` for store 43's open orders.
- **W03 (`22.797 ms`):** `InitPlan 4` (`Index Scan using orders_pkey` discarding 149,895 rows!) + `SubPlan 2` (`Index Scan using riders_pkey` scanning 37 riders) + `Update on orders`. Walks almost the entire `orders_pkey` index from `order_id = 1` to find the oldest `PACKING` order.
- **W04 (`1.236 ms`):** `Bitmap Index Scan` + `Bitmap Heap Scan on store_inventory` (via `store_inventory_pkey` on `store_id = 43`) + `Update on store_inventory`. Already fast at store 43, reading 1,050 store rows and updating 229.
- **W05 (`57.514 ms`):** `Seq Scan on inventory_movements` + `Delete on inventory_movements`. Scans all 90,000 rows to delete 60,165 pre-2026 rows (~67% of the table) and updates `inventory_movements_pkey`.

