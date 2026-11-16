-- =====================================================================
-- Blinkit 10-Minute Grocery Delivery Database
-- Phase 2: Normalized Relational Schema (Constraints Only - No Tuning Indexes)
-- PostgreSQL 15+
-- =====================================================================

DROP SCHEMA IF EXISTS blinkit CASCADE;
CREATE SCHEMA blinkit;
SET search_path TO blinkit;

-- 1. Cities
CREATE TABLE cities (
    city_id   SMALLINT    PRIMARY KEY,
    city_name VARCHAR(50) NOT NULL,
    state     VARCHAR(50) NOT NULL,
    CONSTRAINT uq_cities_name UNIQUE (city_name)
);

-- 2. Categories
CREATE TABLE categories (
    category_id   SMALLINT    PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL,
    is_perishable BOOLEAN     NOT NULL,
    CONSTRAINT uq_categories_name UNIQUE (category_name)
);

-- 3. Dark Stores
CREATE TABLE dark_stores (
    store_id         INTEGER      PRIMARY KEY,
    store_code       VARCHAR(10)  NOT NULL,
    city_id          SMALLINT     NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    latitude         NUMERIC(9,6) NOT NULL,
    longitude        NUMERIC(9,6) NOT NULL,
    opened_on        DATE         NOT NULL,
    is_active        BOOLEAN      NOT NULL,
    max_daily_orders SMALLINT     NOT NULL,
    CONSTRAINT uq_dark_stores_code   UNIQUE (store_code),
    CONSTRAINT chk_store_code_format CHECK (store_code ~ '^[A-Z]{3}-[A-Z]{3}-[0-9]{2}$'),
    CONSTRAINT chk_store_coords      CHECK (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180),
    CONSTRAINT chk_store_max_orders  CHECK (max_daily_orders > 0)
);

-- 4. Products
CREATE TABLE products (
    product_id      INTEGER       PRIMARY KEY,
    sku             VARCHAR(12)   NOT NULL,
    product_name    VARCHAR(120)  NOT NULL,
    brand           VARCHAR(60)   NOT NULL,
    category_id     SMALLINT      NOT NULL REFERENCES categories(category_id) ON DELETE RESTRICT,
    pack_size       VARCHAR(30)   NOT NULL,
    mrp             NUMERIC(10,2) NOT NULL,
    shelf_life_days SMALLINT,
    is_active       BOOLEAN       NOT NULL,
    CONSTRAINT uq_products_sku         UNIQUE (sku),
    CONSTRAINT chk_product_sku_format  CHECK (sku ~ '^BK[0-9]{8}$'),
    CONSTRAINT chk_product_mrp_pos     CHECK (mrp > 0),
    CONSTRAINT chk_product_shelf_life  CHECK (shelf_life_days IS NULL OR shelf_life_days > 0)
);

-- 5. Store Inventory (store x product stock & store-specific price)
CREATE TABLE store_inventory (
    store_id         INTEGER       NOT NULL REFERENCES dark_stores(store_id) ON DELETE RESTRICT,
    product_id       INTEGER       NOT NULL REFERENCES products(product_id)   ON DELETE RESTRICT,
    quantity_on_hand INTEGER       NOT NULL,
    reorder_level    INTEGER       NOT NULL,
    selling_price    NUMERIC(10,2) NOT NULL,
    updated_at       TIMESTAMPTZ   NOT NULL,
    PRIMARY KEY (store_id, product_id),
    CONSTRAINT chk_inv_qty_nonneg     CHECK (quantity_on_hand >= 0),
    CONSTRAINT chk_inv_reorder_nonneg CHECK (reorder_level >= 0),
    CONSTRAINT chk_inv_price_pos      CHECK (selling_price > 0)
);

-- 6. Customers
CREATE TABLE customers (
    customer_id INTEGER      PRIMARY KEY,
    full_name   VARCHAR(100) NOT NULL,
    phone       VARCHAR(10)  NOT NULL,
    email       VARCHAR(150),
    city_id     SMALLINT     NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    created_at  TIMESTAMPTZ  NOT NULL,
    CONSTRAINT uq_customers_phone       UNIQUE (phone),
    CONSTRAINT uq_customers_email       UNIQUE (email),
    CONSTRAINT chk_customer_phone_fmt   CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT chk_customer_email_fmt   CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

-- 7. Riders
CREATE TABLE riders (
    rider_id  INTEGER      PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone     VARCHAR(10)  NOT NULL,
    store_id  INTEGER      NOT NULL REFERENCES dark_stores(store_id) ON DELETE RESTRICT,
    joined_on DATE         NOT NULL,
    status    VARCHAR(20)  NOT NULL,
    CONSTRAINT uq_riders_phone       UNIQUE (phone),
    CONSTRAINT chk_rider_phone_fmt   CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT chk_rider_status      CHECK (status IN ('ACTIVE', 'ON_LEAVE', 'EXITED'))
);

-- 8. Orders
CREATE TABLE orders (
    order_id         BIGINT        PRIMARY KEY,
    customer_id      INTEGER       NOT NULL REFERENCES customers(customer_id)  ON DELETE RESTRICT,
    store_id         INTEGER       NOT NULL REFERENCES dark_stores(store_id) ON DELETE RESTRICT,
    rider_id         INTEGER                REFERENCES riders(rider_id)      ON DELETE SET NULL,
    placed_at        TIMESTAMPTZ   NOT NULL,
    packed_at        TIMESTAMPTZ,
    picked_up_at     TIMESTAMPTZ,
    delivered_at     TIMESTAMPTZ,
    promised_minutes SMALLINT      NOT NULL DEFAULT 10,
    subtotal         NUMERIC(10,2) NOT NULL,
    delivery_fee     NUMERIC(10,2) NOT NULL,
    handling_fee     NUMERIC(10,2) NOT NULL,
    small_cart_fee   NUMERIC(10,2) NOT NULL,
    total_amount     NUMERIC(10,2) NOT NULL,
    payment_method   VARCHAR(20)   NOT NULL,
    status           VARCHAR(20)   NOT NULL,
    CONSTRAINT chk_order_status         CHECK (status IN ('PLACED', 'PACKING', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT chk_order_payment_method CHECK (payment_method IN ('UPI', 'COD', 'CARD', 'WALLET')),
    CONSTRAINT chk_order_promised_pos   CHECK (promised_minutes > 0),
    CONSTRAINT chk_order_amounts_nonneg CHECK (
        subtotal >= 0 AND delivery_fee >= 0 AND handling_fee >= 0 AND small_cart_fee >= 0 AND total_amount >= 0
    ),
    CONSTRAINT chk_order_total_calc     CHECK (
        total_amount = subtotal + delivery_fee + handling_fee + small_cart_fee
    ),
    CONSTRAINT chk_order_delivery_rule  CHECK (
        (subtotal >= 199 AND delivery_fee = 0) OR (subtotal < 199 AND delivery_fee > 0)
    ),
    CONSTRAINT chk_order_time_sequence  CHECK (
        (packed_at    IS NULL OR packed_at >= placed_at)
        AND (picked_up_at IS NULL OR (packed_at IS NOT NULL AND picked_up_at >= packed_at))
        AND (delivered_at IS NULL OR (picked_up_at IS NOT NULL AND delivered_at >= picked_up_at))
    ),
    CONSTRAINT chk_order_lifecycle      CHECK (
        (status = 'PLACED'           AND rider_id IS NULL     AND packed_at IS NULL     AND picked_up_at IS NULL     AND delivered_at IS NULL)
        OR (status = 'PACKING'       AND rider_id IS NULL                               AND picked_up_at IS NULL     AND delivered_at IS NULL)
        OR (status = 'OUT_FOR_DELIVERY' AND rider_id IS NOT NULL AND packed_at IS NOT NULL AND picked_up_at IS NOT NULL AND delivered_at IS NULL)
        OR (status = 'DELIVERED'     AND rider_id IS NOT NULL AND packed_at IS NOT NULL AND picked_up_at IS NOT NULL AND delivered_at IS NOT NULL)
        OR (status = 'CANCELLED'     AND rider_id IS NULL                               AND picked_up_at IS NULL     AND delivered_at IS NULL)
    )
);

-- 9. Order Items
CREATE TABLE order_items (
    order_id              BIGINT        NOT NULL REFERENCES orders(order_id)              ON DELETE CASCADE,
    product_id            INTEGER       NOT NULL REFERENCES products(product_id)          ON DELETE RESTRICT,
    quantity_ordered      SMALLINT      NOT NULL,
    quantity_delivered    SMALLINT      NOT NULL,
    unit_price            NUMERIC(10,2) NOT NULL,
    substitute_product_id INTEGER                REFERENCES products(product_id)          ON DELETE SET NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT chk_oi_qty_ordered_pos    CHECK (quantity_ordered > 0),
    CONSTRAINT chk_oi_qty_deliv_bounds   CHECK (quantity_delivered >= 0 AND quantity_delivered <= quantity_ordered),
    CONSTRAINT chk_oi_unit_price_pos     CHECK (unit_price > 0),
    CONSTRAINT chk_oi_substitute_rule    CHECK (
        substitute_product_id IS NULL
        OR (substitute_product_id <> product_id AND quantity_delivered < quantity_ordered)
    )
);

-- 10. Inventory Movements (composite FK to store_inventory)
CREATE TABLE inventory_movements (
    movement_id   BIGINT      PRIMARY KEY,
    store_id      INTEGER     NOT NULL,
    product_id    INTEGER     NOT NULL,
    movement_type VARCHAR(20) NOT NULL,
    quantity      INTEGER     NOT NULL,
    moved_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_mov_store_inventory FOREIGN KEY (store_id, product_id)
        REFERENCES store_inventory(store_id, product_id) ON DELETE RESTRICT,
    CONSTRAINT chk_mov_type CHECK (movement_type IN ('RESTOCK', 'DAMAGE', 'EXPIRY', 'ADJUSTMENT')),
    CONSTRAINT chk_mov_qty_sign CHECK (
        (movement_type = 'RESTOCK' AND quantity > 0)
        OR (movement_type IN ('DAMAGE', 'EXPIRY') AND quantity < 0)
        OR (movement_type = 'ADJUSTMENT' AND quantity <> 0)
    )
);