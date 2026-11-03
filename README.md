# Blinkit 10-Minute Grocery Delivery Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 10 CSV files (675,000 orders): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details

- Team Number: T0053
- Section: A
- DE Repository: https://github.com/mrinal-create/DE_Project_2026.git

| Role | Name | Enrollment No. | GitHub Username |
|---|---|---|---|
| Group Lead | Moksh Bansal | 2501010279 | firewallls |
| Member 2 | Mrinal Upreti | 2501010282 | mrinal-create |
| Member 3 | Abhishek Pradhan | 2501010018 | abhishek01012008 |
| Member 4 | Subham Sekhar Mandal | 2501010461 | subham-sekhar-mandal |

**Team No.:** T0053 · **Section:** A · **Repository URL:** https://github.com/mrinal-create/DE_Project_2026.git

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

Blinkit promises groceries in **10 minutes**. That only works because every order is served from a nearby **dark store**—a small warehouse with its own **inventory** of products (stock on hand, reorder level and a store-specific selling price). A customer's order is packed, handed to a **rider** and delivered; if an item runs out while packing, it is delivered short or replaced by a **substitute**. Stores are restocked and lose stock to damage and expiry, all recorded as **inventory movements**. Small carts pay extra fees. You have joined the Blinkit data team.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "**Store assignment** and the **category/search pages** must answer instantly—every second counts in a 10-minute promise." | Customer app | R01, R02, R03, R04, R05 |
| P2 | "**Order tracking** and checkout (stock check, placing the order) slow down at peak hours." | Customer app | R06, W01 |
| P3 | "**Store screens**: open orders, rider dispatch and stock deduction after packing lag." | Dark-store operations | R07, R21, W02, W03 |
| P4 | "**Replenishment**: low-stock lists, restocks and dead stock are too slow to run every hour." | Supply chain | R09, R18, R24, W04 |
| P5 | "The category team's "**products not used as substitutes this month**" list is always **empty**." | Category team | R13 |
| P6 | "**SLA, fill-rate, wastage and rider** reports time out." | Operations | R08, R10, R11, R14, R15 |
| P7 | "Growth and finance (cohorts, small-cart fees, GMV, loyalty, recommendations, category sales) are slow, and orders will grow **20×**." | Growth / Finance | R12, R16, R17, R19, R20, R22, R23, R25, W05 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P7, write in your own words what the business needs and which **stakeholder** is affected (customer, dark-store manager, picker/packer, rider, supply chain/replenishment, category team, finance, growth, support).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 10 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `cities.csv` | 10 | Cities |
| `dark_stores.csv` | 120 | Dark stores (micro-warehouses) |
| `categories.csv` | 12 | Product categories |
| `products.csv` | 1,500 | Product catalogue |
| `store_inventory.csv` | 126,000 | Stock and price of each product in each dark store |
| `customers.csv` | 40,000 | Customers |
| `riders.csv` | 1,800 | Delivery riders (each attached to a store) |
| `orders.csv` | 150,000 | Every order from 1 Jan 2025 to 30 Jun 2026 |
| `order_items.csv` | 675,000 | Products in each order (ordered vs delivered quantity, substitutes) |
| `inventory_movements.csv` | 90,000 | Restocks, damages, expiries and adjustments |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**cities.csv**
```
city_id,city_name,state
1,Bengaluru,Karnataka
2,Mumbai,Maharashtra
```

**dark_stores.csv**
```
store_id,store_code,city_id,latitude,longitude,opened_on,is_active,max_daily_orders
1,MUM-AND-11,2,19.113800,72.809285,2023-11-16,t,1500
2,HYD-GAC-21,4,17.419092,78.438015,2022-07-25,t,1500
```

**categories.csv**
```
category_id,category_name,is_perishable
1,Dairy,t
2,Fruits & Vegetables,t
```

**products.csv**
```
product_id,sku,product_name,brand,category_id,pack_size,mrp,shelf_life_days,is_active
1,BK10007919,Vim Detergent 1 kg,Vim,8,1 kg,164.00,,t
2,BK10015838,Kurkure Bhujia 200 g,Kurkure,3,200 g,57.00,,t
```

**store_inventory.csv**
```
store_id,product_id,quantity_on_hand,reorder_level,selling_price,updated_at
1,1,21,7,146.00,2026-06-30 04:00:00+05:30
1,2,28,8,52.00,2026-06-30 03:00:00+05:30
```

**customers.csv**
```
customer_id,full_name,phone,email,city_id,created_at
1,Vivaan Sharma,6300000001,,3,2024-02-08 09:18:56+05:30
2,Aditya Sharma,6300000002,,8,2026-05-04 02:23:33+05:30
```

**riders.csv**
```
rider_id,full_name,phone,store_id,joined_on,status
1,Ananya Gupta,6100000001,1,2025-05-21,ACTIVE
2,Kavya Khan,6100000002,2,2023-11-05,ACTIVE
```

**orders.csv**
```
order_id,customer_id,store_id,rider_id,placed_at,packed_at,picked_up_at,delivered_at,promised_minutes,subtotal,delivery_fee,handling_fee,small_cart_fee,total_amount,payment_method,status
1,14391,54,894,2025-01-01 00:00:00+05:30,2025-01-01 00:02:10+05:30,2025-01-01 00:03:49+05:30,2025-01-01 00:13:44+05:30,10,453.00,0.00,6.00,0.00,459.00,UPI,DELIVERED
2,4263,67,307,2025-01-01 00:05:14+05:30,2025-01-01 00:08:49+05:30,2025-01-01 00:10:39+05:30,2025-01-01 00:14:40+05:30,10,602.00,0.00,2.00,0.00,604.00,COD,DELIVERED
```

**order_items.csv**
```
order_id,product_id,quantity_ordered,quantity_delivered,unit_price,substitute_product_id
1,39,1,1,112.00,
1,426,3,3,77.00,
```

**inventory_movements.csv**
```
movement_id,store_id,product_id,movement_type,quantity,moved_at
1,27,674,ADJUSTMENT,-3,2025-01-01 00:00:00+05:30
2,44,382,RESTOCK,50,2025-01-01 00:08:00+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (Look closely at `store_inventory` and `order_items`. How should `inventory_movements` point to an inventory row?)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. When are `rider_id`, `packed_at`, `picked_up_at`, `delivered_at`, `substitute_product_id`, `shelf_life_days` and `email` empty?
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for formats (store codes, SKUs), allowed values (statuses, movement types, payment methods), time order (placed → packed → picked up → delivered), quantity rules (delivered ≤ ordered, the sign of a movement depends on its type), and money rules (how `total_amount` is built; when the delivery, handling and small-cart fees apply).
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: `orders.subtotal` vs `order_items`; the fee columns vs `subtotal`; `store_inventory.quantity_on_hand` vs the movements and sales) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`blinkit`**: `CREATE SCHEMA blinkit;` and `SET search_path TO blinkit;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO blinkit;
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "every ordered product is stocked by the order's store", "a rider only delivers orders of their own store", "a substitute is a product the same store stocks"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 10 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **noticeably longer** than the others on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Store assignment: the nearest active dark store within ~3 km of a customer at (12.93, 77.62) | READ | | | | |
| R02: Category page: Dairy products in stock at store 43, cheapest first | READ | | | | |
| R03: Search: products with "milk" in the name that are in stock at store 43 | READ | | | | |
| R04: Product page: stock of product 1236 in every Bengaluru dark store | READ | | | | |
| R05: Cart check: current stock and price of 4 cart items at store 43 | READ | | | | |
| R06: Order tracking: customer 1027's latest order with its timeline | READ | | | | |
| R07: Store screen: open orders at store 43 (not yet delivered or cancelled) | READ | | | | |
| R08: SLA report: share of June 2026 deliveries that took longer than promised, per store | READ | | | | |
| R09: Replenishment: products at store 43 at or below their reorder level | READ | | | | |
| R10: Wastage: units lost to expiry or damage per category in June 2026 | READ | | | | |
| R11: Rider performance: average minutes from pickup to delivery per rider at store 43 (June 2026) | READ | | | | |
| R12: Recommendations: products most often bought together with product 1236 | READ | | | | |
| R13: Category team: active products that were never given as a substitute in June 2026 | READ | | | | |
| R14: Fill rate: share of order lines delivered short, per store, June 2026 | READ | | | | |
| R15: Staffing: orders per hour at Bengaluru stores on 29 June 2026 | READ | | | | |
| R16: Growth: monthly cohorts—customers by month of first order, and how many ordered again in June 2026 | READ | | | | |
| R17: Finance: small-cart fee collected per city per month in 2026 | READ | | | | |
| R18: Dead stock: products in stock at store 43 that did not sell there in June 2026 | READ | | | | |
| R19: Category report: June 2026 units sold of every Fruits & Vegetables product | READ | | | | |
| R20: Finance: daily GMV and running total for June 2026 | READ | | | | |
| R21: Store manager: active riders of store 43 with no delivery on 30 June 2026 | READ | | | | |
| R22: Support console: all orders, newest first, page 4,001 (25 per page) | READ | | | | |
| R23: Warehouse scanner: look up a product by SKU | READ | | | | |
| R24: Supply chain: units restocked per product at store 43 in the last 7 days of June 2026 | READ | | | | |
| R25: Loyalty: 20 Mumbai customers with the most delivered orders in 2026 | READ | | | | |
| W01: Checkout: place a new order at store 43 | WRITE | | | | |
| W02: Packing done: reduce store 43's stock for every line of its most recent PLACED or PACKING order | WRITE | | | | |
| W03: Dispatch: give the oldest PACKING order (anywhere) to its store's first active rider | WRITE | | | | |
| W04: Nightly replenishment at store 43: top up everything at or below reorder level | WRITE | | | | |
| W05: Data retention: delete inventory movements older than 1 January 2026 | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R02 | | e.g. Seq Scan on 126k store_inventory rows | e.g. use the `(store_id, product_id)` primary key + index on `products(category_id)` | | e.g. 95% (20×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 675,000 orders. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 10 CSV files with about **20× the rows** (≈ 3,000,000 orders, ≈ 13,500,000 order items, ≈ 2,520,000 store inventory, ≈ 1,800,000 inventory movements, ≈ 800,000 customers). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R22 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / customer and store screens | R01, R02, R03, R04, R05, R06, R07, R09, R21, R23, W01, W02, W03, W04 | **under 5 ms** |
| Interactive operations tools | R11, R12, R13, R15, R18, R22, R24 | **under 250 ms** |
| Reports and analytics | R08, R10, R14, R16, R17, R19, R20, R25 | **under 5,000 ms** |
| Batch jobs | W05 | **under 1,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `order_items`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard by city, by dark store, or by customer? Nearly everything a store does is local—but cohorts and finance span all stores. Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `order_items`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
blinkit-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Tue 3 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Store assignment: the nearest active dark store within ~3 km of a customer at (12.93, 77.62)**
```sql
SELECT store_id, store_code,
       round((6371 * acos(least(1, cos(radians(12.93)) * cos(radians(latitude)) * cos(radians(longitude) - radians(77.62))
                                  + sin(radians(12.93)) * sin(radians(latitude)))))::numeric, 2) AS km
FROM dark_stores
WHERE is_active
  AND latitude  BETWEEN 12.93 - 0.027 AND 12.93 + 0.027
  AND longitude BETWEEN 77.62 - 0.028 AND 77.62 + 0.028
ORDER BY km
LIMIT 1;
```

**R02: Category page: Dairy products in stock at store 43, cheapest first**
```sql
SELECT p.product_id, p.product_name, si.selling_price, si.quantity_on_hand
FROM store_inventory si
JOIN products p   ON p.product_id = si.product_id
JOIN categories c ON c.category_id = p.category_id
WHERE si.store_id = 43
  AND c.category_name = 'Dairy'
  AND si.quantity_on_hand > 0
ORDER BY si.selling_price;
```

**R03: Search: products with "milk" in the name that are in stock at store 43**
```sql
SELECT p.product_id, p.product_name, si.selling_price
FROM products p
JOIN store_inventory si ON si.product_id = p.product_id AND si.store_id = 43
WHERE p.product_name ILIKE '%milk%'
  AND si.quantity_on_hand > 0
ORDER BY si.selling_price;
```

**R04: Product page: stock of product 1236 in every Bengaluru dark store**
```sql
SELECT s.store_code, si.quantity_on_hand, si.selling_price
FROM store_inventory si
JOIN dark_stores s ON s.store_id = si.store_id
WHERE si.product_id = 1236 AND s.city_id = 1
ORDER BY si.quantity_on_hand DESC;
```

**R05: Cart check: current stock and price of 4 cart items at store 43**
```sql
SELECT product_id, quantity_on_hand, selling_price
FROM store_inventory
WHERE store_id = 43 AND product_id IN (1236, 324, 101, 777);
```

**R06: Order tracking: customer 1027's latest order with its timeline**
```sql
SELECT order_id, status, placed_at, packed_at, picked_up_at, delivered_at, total_amount
FROM orders
WHERE customer_id = 1027
ORDER BY placed_at DESC
LIMIT 1;
```

**R07: Store screen: open orders at store 43 (not yet delivered or cancelled)**
```sql
SELECT order_id, status, placed_at, rider_id
FROM orders
WHERE store_id = 43 AND status IN ('PLACED', 'PACKING', 'OUT_FOR_DELIVERY')
ORDER BY placed_at;
```

**R08: SLA report: share of June 2026 deliveries that took longer than promised, per store**
```sql
SELECT store_id, count(*) AS deliveries,
       round(100.0 * count(*) FILTER (WHERE delivered_at - placed_at > promised_minutes * interval '1 minute') / count(*), 1) AS late_pct
FROM orders
WHERE status = 'DELIVERED'
  AND placed_at >= '2026-06-01' AND placed_at < '2026-07-01'
GROUP BY store_id
ORDER BY late_pct DESC;
```

**R09: Replenishment: products at store 43 at or below their reorder level**
```sql
SELECT p.product_id, p.product_name, si.quantity_on_hand, si.reorder_level
FROM store_inventory si
JOIN products p ON p.product_id = si.product_id
WHERE si.store_id = 43
  AND si.quantity_on_hand <= si.reorder_level
ORDER BY si.quantity_on_hand;
```

**R10: Wastage: units lost to expiry or damage per category in June 2026**
```sql
SELECT c.category_name, m.movement_type, -sum(m.quantity) AS units_lost
FROM inventory_movements m
JOIN products p   ON p.product_id = m.product_id
JOIN categories c ON c.category_id = p.category_id
WHERE m.movement_type IN ('EXPIRY', 'DAMAGE')
  AND m.moved_at >= '2026-06-01' AND m.moved_at < '2026-07-01'
GROUP BY c.category_name, m.movement_type
ORDER BY units_lost DESC;
```

**R11: Rider performance: average minutes from pickup to delivery per rider at store 43 (June 2026)**
```sql
SELECT rider_id, count(*) AS deliveries,
       round(avg(EXTRACT(EPOCH FROM (delivered_at - picked_up_at)) / 60), 1) AS avg_ride_minutes
FROM orders
WHERE store_id = 43 AND status = 'DELIVERED'
  AND placed_at >= '2026-06-01' AND placed_at < '2026-07-01'
GROUP BY rider_id
ORDER BY avg_ride_minutes;
```

**R12: Recommendations: products most often bought together with product 1236**
```sql
SELECT b.product_id, count(*) AS together
FROM order_items a
JOIN order_items b ON b.order_id = a.order_id AND b.product_id <> a.product_id
WHERE a.product_id = 1236
GROUP BY b.product_id
ORDER BY together DESC
LIMIT 10;
```

**R13: Category team: active products that were never given as a substitute in June 2026**
```sql
SELECT p.product_id, p.product_name
FROM products p
WHERE p.is_active
  AND p.product_id NOT IN (SELECT oi.substitute_product_id
                           FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
                           WHERE o.placed_at >= '2026-06-01' AND o.placed_at < '2026-07-01');
```

**R14: Fill rate: share of order lines delivered short, per store, June 2026**
```sql
SELECT o.store_id, count(*) AS lines,
       round(100.0 * count(*) FILTER (WHERE oi.quantity_delivered < oi.quantity_ordered) / count(*), 2) AS short_pct
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.placed_at >= '2026-06-01' AND o.placed_at < '2026-07-01'
GROUP BY o.store_id
ORDER BY short_pct DESC;
```

**R15: Staffing: orders per hour at Bengaluru stores on 29 June 2026**
```sql
SELECT o.store_id, EXTRACT(HOUR FROM o.placed_at) AS hour, count(*) AS orders
FROM orders o
JOIN dark_stores s ON s.store_id = o.store_id
WHERE s.city_id = 1
  AND DATE(o.placed_at) = '2026-06-29'
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R16: Growth: monthly cohorts—customers by month of first order, and how many ordered again in June 2026**
```sql
WITH firsts AS (
    SELECT customer_id, date_trunc('month', min(placed_at)) AS cohort
    FROM orders
    GROUP BY customer_id
)
SELECT f.cohort, count(*) AS customers,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = f.customer_id
                                      AND o.placed_at >= '2026-06-01')) AS active_in_june
FROM firsts f
GROUP BY f.cohort
ORDER BY f.cohort;
```

**R17: Finance: small-cart fee collected per city per month in 2026**
```sql
SELECT s.city_id, date_trunc('month', o.placed_at) AS month, sum(o.small_cart_fee) AS small_cart_fees
FROM orders o
JOIN dark_stores s ON s.store_id = o.store_id
WHERE EXTRACT(YEAR FROM o.placed_at) = 2026
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R18: Dead stock: products in stock at store 43 that did not sell there in June 2026**
```sql
SELECT p.product_id, p.product_name, si.quantity_on_hand
FROM store_inventory si
JOIN products p ON p.product_id = si.product_id
WHERE si.store_id = 43 AND si.quantity_on_hand > 0
  AND NOT EXISTS (SELECT 1 FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
                  WHERE oi.product_id = si.product_id AND o.store_id = 43
                    AND o.placed_at >= '2026-06-01')
ORDER BY si.quantity_on_hand DESC;
```

**R19: Category report: June 2026 units sold of every Fruits & Vegetables product**
```sql
SELECT p.product_id, p.product_name,
       (SELECT coalesce(sum(oi.quantity_delivered), 0)
          FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
         WHERE oi.product_id = p.product_id
           AND o.placed_at >= '2026-06-01' AND o.placed_at < '2026-07-01') AS units_sold
FROM products p
WHERE p.category_id = (SELECT category_id FROM categories WHERE category_name = 'Fruits & Vegetables')
ORDER BY units_sold DESC;
```

**R20: Finance: daily GMV and running total for June 2026**
```sql
SELECT day, gmv, sum(gmv) OVER (ORDER BY day) AS running_gmv
FROM (
    SELECT placed_at::date AS day, sum(total_amount) AS gmv
    FROM orders
    WHERE status = 'DELIVERED'
      AND placed_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**R21: Store manager: active riders of store 43 with no delivery on 30 June 2026**
```sql
SELECT r.rider_id, r.full_name
FROM riders r
WHERE r.store_id = 43 AND r.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.rider_id = r.rider_id AND o.placed_at >= '2026-06-30')
ORDER BY r.rider_id;
```

**R22: Support console: all orders, newest first, page 4,001 (25 per page)**
```sql
SELECT order_id, customer_id, store_id, status, total_amount, placed_at
FROM orders
ORDER BY placed_at DESC
OFFSET 100000
LIMIT 25;
```

**R23: Warehouse scanner: look up a product by SKU**
```sql
SELECT product_id, product_name, pack_size, mrp
FROM products
WHERE sku = 'BK19787884';
```

**R24: Supply chain: units restocked per product at store 43 in the last 7 days of June 2026**
```sql
SELECT m.product_id, count(*) AS restocks, sum(m.quantity) AS units
FROM inventory_movements m
WHERE m.store_id = 43 AND m.movement_type = 'RESTOCK'
  AND m.moved_at >= '2026-06-24'
GROUP BY m.product_id
ORDER BY units DESC;
```

**R25: Loyalty: 20 Mumbai customers with the most delivered orders in 2026**
```sql
SELECT o.customer_id, count(*) AS orders, sum(o.total_amount) AS spend
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE c.city_id = 2 AND o.status = 'DELIVERED' AND o.placed_at >= '2026-01-01'
GROUP BY o.customer_id
ORDER BY orders DESC, spend DESC
LIMIT 20;
```

**W01: Checkout: place a new order at store 43**
```sql
INSERT INTO orders (order_id, customer_id, store_id, placed_at, subtotal, delivery_fee, handling_fee, small_cart_fee,
                    total_amount, payment_method, status)
VALUES (90000001, 1027, 43, '2026-07-01 08:00:00+05:30', 245.00, 0, 6, 0, 251.00, 'UPI', 'PLACED');
```

**W02: Packing done: reduce store 43's stock for every line of its most recent PLACED or PACKING order**
```sql
UPDATE store_inventory si
SET quantity_on_hand = greatest(0, si.quantity_on_hand - oi.quantity_ordered),
    updated_at = '2026-07-01 08:05:00+05:30'
FROM order_items oi
WHERE oi.order_id = (SELECT max(order_id) FROM orders WHERE store_id = 43 AND status IN ('PLACED', 'PACKING'))
  AND si.store_id = 43
  AND si.product_id = oi.product_id;
```

**W03: Dispatch: give the oldest PACKING order (anywhere) to its store's first active rider**
```sql
UPDATE orders o
SET rider_id = (SELECT min(r.rider_id) FROM riders r WHERE r.store_id = o.store_id AND r.status = 'ACTIVE'),
    status = 'OUT_FOR_DELIVERY',
    picked_up_at = coalesce(o.packed_at, o.placed_at) + interval '1 minute',
    packed_at = coalesce(o.packed_at, o.placed_at + interval '30 seconds')
WHERE o.order_id = (SELECT min(order_id) FROM orders WHERE status = 'PACKING');
```

**W04: Nightly replenishment at store 43: top up everything at or below reorder level**
```sql
UPDATE store_inventory
SET quantity_on_hand = reorder_level * 4, updated_at = '2026-07-01 05:00:00+05:30'
WHERE store_id = 43 AND quantity_on_hand <= reorder_level;
```

**W05: Data retention: delete inventory movements older than 1 January 2026**
```sql
DELETE FROM inventory_movements
WHERE moved_at < '2026-01-01';
```
