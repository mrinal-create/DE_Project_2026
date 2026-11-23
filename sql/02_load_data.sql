-- =====================================================================
-- Blinkit 10-Minute Grocery Delivery Database
-- Phase 2: Load Seed CSVs in Topological Order + Verify Counts
-- Run from project root: psql -d <your_db> -f sql/02_load_data.sql
-- =====================================================================

SET search_path TO blinkit;

\copy cities              FROM 'large_data/cities.csv'              WITH (FORMAT csv, HEADER true)
\copy categories          FROM 'large_data/categories.csv'          WITH (FORMAT csv, HEADER true)
\copy dark_stores         FROM 'large_data/dark_stores.csv'         WITH (FORMAT csv, HEADER true)
\copy products            FROM 'large_data/products.csv'            WITH (FORMAT csv, HEADER true)
\copy store_inventory     FROM 'large_data/store_inventory.csv'     WITH (FORMAT csv, HEADER true)
\copy customers           FROM 'large_data/customers.csv'           WITH (FORMAT csv, HEADER true)
\copy riders              FROM 'large_data/riders.csv'              WITH (FORMAT csv, HEADER true)
\copy orders              FROM 'large_data/orders.csv'              WITH (FORMAT csv, HEADER true)
\copy order_items         FROM 'large_data/order_items.csv'         WITH (FORMAT csv, HEADER true)
\copy inventory_movements FROM 'large_data/inventory_movements.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;

SELECT 'cities'              AS table_name, count(*) AS row_count FROM cities
UNION ALL SELECT 'categories',          count(*) FROM categories
UNION ALL SELECT 'dark_stores',         count(*) FROM dark_stores
UNION ALL SELECT 'products',            count(*) FROM products
UNION ALL SELECT 'store_inventory',     count(*) FROM store_inventory
UNION ALL SELECT 'customers',           count(*) FROM customers
UNION ALL SELECT 'riders',              count(*) FROM riders
UNION ALL SELECT 'orders',              count(*) FROM orders
UNION ALL SELECT 'order_items',         count(*) FROM order_items
UNION ALL SELECT 'inventory_movements', count(*) FROM inventory_movements
ORDER BY table_name;