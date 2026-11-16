# Phase 1: Problem Understanding

**Project:** Blinkit 10-Minute Grocery Delivery Database (`T0053`, Section A)  
**Goal:** Rebuild a normalized, constraint-enforced PostgreSQL schema from raw CSV exports, establish baseline query performance across the 30 core SQL workloads (`R01`–`R25`, `W01`–`W05`), optimize them without altering results (and fix any broken SQL semantics), and verify readiness for 20×–100× scale.

---

## 1. Problem Analysis, Stakeholders & Workload Classification

| ID | Business Need (in our own words) | Primary Stakeholders | Related Queries | Classification | Target Latency (at 20×) |
|---|---|---|---|---|---|
| **P1** | Instantly match a customer's GPS coordinates to the nearest active dark store within ~3 km, load category listings, run product search, inspect store stock, and validate cart prices/availability before checkout. Every extra second breaks the 10-minute delivery UX. | Customer, Growth (conversion) | `R01`–`R05` | **Customer-facing / Real-time** | `< 5 ms` |
| **P2** | Display live order status timelines (`PLACED` → `PACKING` → `OUT_FOR_DELIVERY` → `DELIVERED`) and commit new checkout orders reliably without peak-hour contention. | Customer, Support | `R06`, `W01` | **Customer-facing / Real-time** | `< 5 ms` |
| **P3** | Power dark-store floor screens: show open orders queued for packing, deduct inventory immediately after packing, assign the oldest `PACKING` order to an active store rider, and spot idle active riders. | Dark-store Manager, Picker/Packer, Rider | `R07`, `R21`, `W02`, `W03` | **Real-time / Store Operations** | `< 5 ms` |
| **P4** | Identify products at or below reorder threshold for hourly replenishment, top up store stock overnight, detect slow-moving/dead inventory, and audit recent restock velocity. | Supply Chain / Replenishment, Dark-store Manager | `R09`, `R18`, `R24`, `W04` | **Mixed:** `R09`/`W04` **Real-time / Store Ops** (`< 5 ms`); `R18`/`R24` **Interactive Ops Tool** (`< 250 ms`) | `< 5 ms` / `< 250 ms` |
| **P5** | Identify active catalog products that were never used as substitutes in the current month so category managers can expand substitute coverage. Currently always returns 0 rows due to a `NULL` trap in SQL (`NOT IN`). | Category Team, Picker/Packer | `R13` | **Interactive Ops / Reporting** (correctness bug + optimization) | `< 250 ms` |
| **P6** | Generate operational KPIs—10-minute SLA breach rate, line-item fill/short-delivery rate, category wastage (`DAMAGE`/`EXPIRY`), rider pickup-to-delivery speed, and hourly store staffing demand—without timing out. | Operations, Dark-store Manager, Supply Chain, Support | `R08`, `R10`, `R11`, `R14`, `R15` | **Reporting / Analytics** (`R11`, `R15` interactive `< 250 ms`; `R08`, `R10`, `R14` batch/analytics `< 5,000 ms`) | `< 250 ms` – `< 5,000 ms` |
| **P7** | Compute customer cohorts, small-cart fees, daily GMV + running totals, top loyalty customers, product co-purchase recommendations, SKU lookups, deep support pagination, and delete expired movement logs—while surviving **20× order growth**. | Finance, Growth, Category Team, Support, Data/Infra | `R12`, `R16`, `R17`, `R19`, `R20`, `R22`, `R23`, `R25`, `W05` | **Mixed:** `R23` **Real-time** (`< 5 ms`); `R12`, `R22` **Interactive** (`< 250 ms`); `R16`, `R17`, `R19`, `R20`, `R25` **Analytics** (`< 5,000 ms`); `W05` **Batch** (`< 1,000 ms`) | `< 5 ms` – `< 5,000 ms` |

---

## 2. Key Assumptions

1. **Time Zone Consistency:** All event timestamps (`placed_at`, `packed_at`, `picked_up_at`, `delivered_at`, `moved_at`, `updated_at`, `created_at`) represent IST (`+05:30`) stored as PostgreSQL `TIMESTAMPTZ` so date-range queries and `date_trunc` behave consistently under the session timezone.
2. **Store-Scoped Inventory & Riders:** Each dark store maintains independent stock and store-specific `selling_price` (`<= products.mrp`), and each rider is attached to one primary dark store and fulfills orders only for that store.
3. **Order Lifecycle & Pricing:** Delivery fee applies below Rs. 199 (`Rs. 25`), handling fee drops from `Rs. 6` to `Rs. 2` at `Rs. 500`, and `orders.subtotal` records the billed delivered-item subtotal (`SUM(quantity_delivered * unit_price)`), with `total_amount = subtotal + delivery_fee + handling_fee + small_cart_fee`.
4. **Historical Snapshot Scope:** Seed exports begin `2025-01-01` for orders and inventory movements without an opening stock snapshot prior to that date; therefore `store_inventory.quantity_on_hand` reflects current operational stock rather than a raw sum of exported movements minus orders.
5. **Catalog Deactivation:** Inactive products (`is_active = false`) and exited/on-leave riders remain referenced by historical orders and order items for audit integrity, so foreign keys must protect historical rows via `RESTRICT` (soft deactivation) rather than cascading deletes.