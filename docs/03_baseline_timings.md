# Phase 3: Baseline Query Timings

**Database:** `blinkit_db` (schema `blinkit`, constraints & auto PK/UNIQUE indexes only — no tuning indexes)  
**Engine:** PostgreSQL 18.6 (Postgres.app) on Apple MacBook Pro  
**Method:** `./benchmarks/run_benchmark.sh blinkit_db baseline` (`EXPLAIN (ANALYZE, BUFFERS)`, 3 runs per query, writes wrapped in `BEGIN ... ROLLBACK`).  
**Raw artifacts:** [summary.csv](../benchmarks/results/baseline/summary.csv) and `benchmarks/results/baseline/{R01..W05}.txt`.

---

## 1. Baseline Timing Table

| **SQL Query** | **Type** | **Run 1 (ms)** | **Run 2 (ms)** | **Run 3 (ms)** | **Average (ms)** |
|---|---|---:|---:|---:|---:|
| R01: Store assignment: the nearest active dark store within ~3 km of a customer at (12.93, 77.62) | READ | 0.112 | 0.058 | 0.056 | 0.075 |
| R02: Category page: Dairy products in stock at store 43, cheapest first | READ | 0.445 | 0.248 | 0.243 | 0.312 |
| R03: Search: products with "milk" in the name that are in stock at store 43 | READ | 0.463 | 0.411 | 0.398 | 0.424 |
| R04: Product page: stock of product 1236 in every Bengaluru dark store | READ | 0.125 | 0.099 | 0.102 | 0.109 |
| R05: Cart check: current stock and price of 4 cart items at store 43 | READ | 0.027 | 0.032 | 0.029 | 0.029 |
| R06: Order tracking: customer 1027's latest order with its timeline | READ | 5.092 | 4.997 | 4.961 | 5.017 |
| R07: Store screen: open orders at store 43 (not yet delivered or cancelled) | READ | 5.925 | 5.579 | 5.401 | 5.635 |
| R08: SLA report: share of June 2026 deliveries that took longer than promised, per store | READ | 5.718 | 5.713 | 5.621 | 5.684 |
| R09: Replenishment: products at store 43 at or below their reorder level | READ | 0.248 | 0.237 | 0.248 | 0.244 |
| R10: Wastage: units lost to expiry or damage per category in June 2026 | READ | 4.683 | 4.545 | 4.742 | 4.657 |
| R11: Rider performance: average minutes from pickup to delivery per rider at store 43 (June 2026) | READ | 5.211 | 5.132 | 5.854 | 5.399 |
| R12: Recommendations: products most often bought together with product 1236 | READ | 8.371 | 8.380 | 8.365 | 8.372 |
| R13: Category team: active products that were never given as a substitute in June 2026 | READ | 19.123 | 18.699 | 19.427 | 19.083 |
| R14: Fill rate: share of order lines delivered short, per store, June 2026 | READ | 18.977 | 18.582 | 18.070 | 18.543 |
| R15: Staffing: orders per hour at Bengaluru stores on 29 June 2026 | READ | 7.948 | 7.872 | 7.808 | 7.876 |
| R16: Growth: monthly cohorts—customers by month of first order, and how many ordered again in June 2026 | READ | 28.472 | 28.670 | 27.885 | 28.342 |
| R17: Finance: small-cart fee collected per city per month in 2026 | READ | 27.841 | 28.493 | 28.080 | 28.138 |
| R18: Dead stock: products in stock at store 43 that did not sell there in June 2026 | READ | 4.764 | 4.702 | 4.610 | 4.692 |
| R19: Category report: June 2026 units sold of every Fruits & Vegetables product | READ | 1820.908 | 1710.160 | 1732.910 | 1754.659 |
| R20: Finance: daily GMV and running total for June 2026 | READ | 9.074 | 9.166 | 7.961 | 8.734 |
| R21: Store manager: active riders of store 43 with no delivery on 30 June 2026 | READ | 4.565 | 4.538 | 4.503 | 4.535 |
| R22: Support console: all orders, newest first, page 4,001 (25 per page) | READ | 36.080 | 36.576 | 35.051 | 35.902 |
| R23: Warehouse scanner: look up a product by SKU | READ | 0.025 | 0.023 | 0.024 | 0.024 |
| R24: Supply chain: units restocked per product at store 43 in the last 7 days of June 2026 | READ | 2.670 | 2.561 | 2.589 | 2.607 |
| R25: Loyalty: 20 Mumbai customers with the most delivered orders in 2026 | READ | 12.571 | 12.330 | 11.886 | 12.262 |
| W01: Checkout: place a new order at store 43 | WRITE | 0.528 | 0.551 | 0.518 | 0.532 |
| W02: Packing done: reduce store 43's stock for every line of its most recent PLACED or PACKING order | WRITE | 9.105 | 9.388 | 9.000 | 9.164 |
| W03: Dispatch: give the oldest PACKING order (anywhere) to its store's first active rider | WRITE | 10.647 | 11.242 | 11.258 | 11.049 |
| W04: Nightly replenishment at store 43: top up everything at or below reorder level | WRITE | 1.875 | 0.680 | 0.493 | 1.016 |
| W05: Data retention: delete inventory movements older than 1 January 2026 | WRITE | 10.465 | 11.097 | 38.301 | 19.954 |
| **Total (sum of all 30)** | | | | | **2003.069** |

- **R01 (`0.075 ms`):** `Seq Scan on dark_stores` + `Sort`. Fast only because `dark_stores` currently has 120 rows; without an active geo index it discards 119 rows.
- **R02 (`0.312 ms`):** `Seq Scan on products` + `Seq Scan on categories` + `Index Scan using store_inventory_pkey on store_inventory` + `Sort`. Fast at seed size via `store_inventory_pkey(store_id, product_id)`, but performs 125 PK probes and sorts in memory instead of scanning pre-filtered inventory.
- **R03 (`0.424 ms`):** `Seq Scan on products` + `Index Scan using store_inventory_pkey` + `Sort`. Slow relative to PK lookup because `ILIKE '%milk%'` scans all 1,500 `products` rows (`1,469` discarded) without a trigram index.
- **R04 (`0.109 ms`):** `Seq Scan on dark_stores` + `Index Scan using store_inventory_pkey` + `Sort`. Probe order works for 19 Bengaluru stores, but `store_inventory_pkey` has `store_id` first, forcing 19 random lookups instead of a single lookup on `product_id`.
- **R05 (`0.029 ms`):** `Index Scan using store_inventory_pkey on store_inventory`. Already optimal (`Index Cond: store_id = 43 AND product_id = ANY(...)`) with 4 index searches.
- **R06 (`5.017 ms`):** `Seq Scan on orders` + `Sort (top-N heapsort)`. Slow for a real-time customer lookup because no index exists on `orders(customer_id, placed_at)`, forcing a full scan of 150,000 orders (`149,991` discarded).
- **R07 (`5.635 ms`):** `Parallel Seq Scan on orders` + `Sort`. Scans all 150,000 orders across 2 workers just to return 2 open orders at store 43 because no `(store_id, status)` / partial open-order index exists.
- **R08 (`5.684 ms`):** `Parallel Seq Scan on orders` + `Partial HashAggregate` + `Sort` + `Finalize GroupAggregate`. Scans all 150,000 `orders` rows (`142,185` discarded across workers) because `placed_at` and `status` are unindexed.
- **R09 (`0.244 ms`):** `Bitmap Index Scan` + `Bitmap Heap Scan on store_inventory` (via `store_inventory_pkey` on `store_id = 43`) + `Hash Join` with `Seq Scan on products` + `Sort`. Reads all 1,050 SKUs of store 43 and discards `821` above reorder level.
- **R10 (`4.657 ms`):** `Seq Scan on inventory_movements` + `Hash Join` (`Seq Scan on products`) + `Index Scan using categories_pkey` + `HashAggregate` + `Sort`. Scans all 90,000 movements (`89,430` discarded) because `moved_at` / `movement_type` are unindexed.
- **R11 (`5.399 ms`):** `Parallel Seq Scan on orders` + `Sort` + `GroupAggregate`. Scans all 150,000 orders to isolate ~69 June delivered orders at store 43 (`149,931` rows discarded).
- **R12 (`8.372 ms`):** `Parallel Seq Scan on order_items a` + `Nested Loop` -> `Index Only Scan using order_items_pkey on order_items b` + `Sort` + `GroupAggregate` + `Limit`. Scans all 675,000 rows of `order_items` to find 466 lines containing `product_id = 1236` because `(order_id, product_id)` cannot seek by `product_id`.
- **R13 (`19.083 ms`):** `Seq Scan on products` + `SubPlan 1` (`Parallel Hash Join` of `Parallel Seq Scan on order_items` and `Parallel Seq Scan on orders`). Scans all 675k order items and 150k orders, **and returns 0 rows (wrong answer!)** because `substitute_product_id` contains `NULL`s inside `NOT IN`.
- **R14 (`18.543 ms`):** `Parallel Hash Join` (`Parallel Seq Scan on order_items` + `Parallel Seq Scan on orders`) + `Partial HashAggregate` + `Finalize GroupAggregate` + `Sort`. Full sequential scans of both `orders` (150k) and `order_items` (675k) because `orders(placed_at)` is unindexed.
- **R15 (`7.876 ms`):** `Seq Scan on orders` + `Nested Loop` -> `Index Scan using dark_stores_pkey` + `Sort` + `GroupAggregate`. Uses non-sargable `DATE(o.placed_at) = '2026-06-29'`, forcing a full 150,000-row scan of `orders` (`149,725` discarded).
- **R16 (`28.342 ms`):** `Seq Scan on orders` (`HashAggregate` for `firsts`) + `SubPlan 2` (`Seq Scan on orders o`) + `Sort` + `GroupAggregate`. Reads the entire 150k-row `orders` table **twice** plus builds and sorts 39,011 customer groups.
- **R17 (`28.138 ms`):** `Seq Scan on orders` + `Index Scan using dark_stores_pkey` + `Sort` + `GroupAggregate`. Uses non-sargable `EXTRACT(YEAR FROM o.placed_at) = 2026`, scanning all 150k orders (`100,275` discarded) and sorting 49,725 tuples.
- **R18 (`4.692 ms`):** `Seq Scan on orders` + `Index Only Scan using order_items_pkey` + `Hash Right Anti Join` with `Bitmap Heap Scan on store_inventory` + `Hash Join` (`Seq Scan on products`). Scans all 150,000 orders (`149,926` discarded) just to get store 43's 74 June orders.
- **R19 (`1754.659 ms`):** `Seq Scan on categories` + `Seq Scan on products` + **correlated `SubPlan 1` executed 125 times**, each doing a full **`Seq Scan on order_items` (675,000 rows)** + 56,292 `Index Scan using orders_pkey`. Accounted for **87.5% of total baseline workload time** due to `O(125 × 675,000)` nested scans!
- **R20 (`8.734 ms`):** `Parallel Seq Scan on orders` + `Sort` + `GroupAggregate` + `WindowAgg`. Non-sargable `placed_at::date BETWEEN ...` forces a full scan of 150,000 orders (`142,185` discarded).
- **R21 (`4.535 ms`):** `Seq Scan on riders` + `Seq Scan on orders` + `Hash Right Anti Join` + `Sort`. Scans all 150,000 orders (`149,726` discarded) and all 1,800 riders (`1,786` discarded) due to missing `(store_id, status)` and `(rider_id, placed_at)` indexes.
- **R22 (`35.902 ms`):** `Seq Scan on orders` + `Sort (external merge Disk: 7352kB)` + `Limit`. Reads and disk-sorts all 150,000 orders only to discard the first 100,000 rows (`OFFSET 100000`).
- **R23 (`0.024 ms`):** `Index Scan using uq_products_sku on products`. Already optimal (`0.042 ms`) thanks to the automatic `UNIQUE` B-tree index on `products(sku)`.
- **R24 (`2.607 ms`):** `Seq Scan on inventory_movements` + `Sort` + `GroupAggregate`. Scans all 90,000 movement rows (`89,993` discarded) to find just 7 matching restock rows for store 43.
- **R25 (`12.262 ms`):** `Hash Join` (`Seq Scan on orders` + `Seq Scan on customers`) + `HashAggregate` + `Sort (top-N heapsort)`. Full scans of 40,000 customers (`33,600` discarded) and 150,000 orders (`102,275` discarded).
- **W01 (`0.532 ms`):** `Insert on orders`. Fast single-row insert validating PK + FK constraints (`customers`, `dark_stores`).
- **W02 (`9.164 ms`):** `InitPlan 1` (`Seq Scan on orders` discarding 149,998 rows!) + `Index Scan using order_items_pkey` + `Index Scan using store_inventory_pkey` + `Update on store_inventory`. Almost all 19.5 ms is wasted scanning 150k orders to find `max(order_id)` for store 43's open orders.
- **W03 (`11.049 ms`):** `InitPlan 4` (`Index Scan using orders_pkey` discarding 149,895 rows!) + `SubPlan 2` (`Index Scan using riders_pkey` scanning 37 riders) + `Update on orders`. Walks almost the entire `orders_pkey` index from `order_id = 1` to find the oldest `PACKING` order.
- **W04 (`1.016 ms`):** `Bitmap Index Scan` + `Bitmap Heap Scan on store_inventory` (via `store_inventory_pkey` on `store_id = 43`) + `Update on store_inventory`. Already fast at store 43, reading 1,050 store rows and updating 229.
- **W05 (`19.954 ms`):** `Seq Scan on inventory_movements` + `Delete on inventory_movements`. Scans all 90,000 rows to delete 60,165 pre-2026 rows (~67% of the table) and updates `inventory_movements_pkey`.