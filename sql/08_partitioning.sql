-- =====================================================================
-- Blinkit 10-Minute Grocery Delivery Database
-- Phase 5 (CP4): Partitioning Design & Partition Pruning Verification
-- Isolated in schema `blinkit_part` so Phase 2-4 schema `blinkit` stays intact.
--
-- PostgreSQL Partitioned Primary-Key Rule:
--   Every PRIMARY KEY or UNIQUE constraint on a partitioned table MUST
--   include all partition key columns (PostgreSQL enforces uniqueness
--   via local per-partition indexes). Therefore:
--     * orders_part      PK = (order_id, placed_at)
--     * order_items_part PK = (order_id, product_id, placed_at)
--     * inv_mov_part     PK = (movement_id, moved_at)
-- =====================================================================

DROP SCHEMA IF EXISTS blinkit_part CASCADE;
CREATE SCHEMA blinkit_part;
SET search_path TO blinkit_part, blinkit;

-- 1. Co-partitioned Orders table (RANGE by placed_at, monthly partitions)
CREATE TABLE orders_part (
    order_id         BIGINT        NOT NULL,
    customer_id      INTEGER       NOT NULL,
    store_id         INTEGER       NOT NULL,
    rider_id         INTEGER,
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
    PRIMARY KEY (order_id, placed_at)
) PARTITION BY RANGE (placed_at);

-- 2. Partitioned Order Items table (RANGE by placed_at, monthly partitions)
--    Denormalizing placed_at onto order_items enables co-partitioned joins and
--    direct time-range partition pruning (e.g., R14, R19) without scanning older months.
CREATE TABLE order_items_part (
    order_id              BIGINT        NOT NULL,
    product_id            INTEGER       NOT NULL,
    placed_at             TIMESTAMPTZ   NOT NULL,
    quantity_ordered      SMALLINT      NOT NULL CHECK (quantity_ordered > 0),
    quantity_delivered    SMALLINT      NOT NULL CHECK (quantity_delivered >= 0 AND quantity_delivered <= quantity_ordered),
    unit_price            NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    substitute_product_id INTEGER,
    PRIMARY KEY (order_id, product_id, placed_at),
    FOREIGN KEY (order_id, placed_at) REFERENCES orders_part (order_id, placed_at) ON DELETE CASCADE
) PARTITION BY RANGE (placed_at);

-- 3. Partitioned Inventory Movements table (RANGE by moved_at, monthly partitions)
--    Turns W05 retention deletes into instant metadata-only DETACH/DROP PARTITION.
CREATE TABLE inventory_movements_part (
    movement_id   BIGINT      NOT NULL,
    store_id      INTEGER     NOT NULL,
    product_id    INTEGER     NOT NULL,
    movement_type VARCHAR(20) NOT NULL CHECK (movement_type IN ('RESTOCK', 'DAMAGE', 'EXPIRY', 'ADJUSTMENT')),
    quantity      INTEGER     NOT NULL CHECK (quantity <> 0),
    moved_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (movement_id, moved_at)
) PARTITION BY RANGE (moved_at);

-- Create monthly partitions for Jan 2025 - Jul 2026 + DEFAULT
DO $$
DECLARE
    m_start DATE := DATE '2025-01-01';
    m_end   DATE;
    suffix  TEXT;
BEGIN
    WHILE m_start < DATE '2026-08-01' LOOP
        m_end  := (m_start + INTERVAL '1 month')::DATE;
        suffix := to_char(m_start, 'YYYY_MM');

        EXECUTE format(
            'CREATE TABLE blinkit_part.orders_%s PARTITION OF blinkit_part.orders_part FOR VALUES FROM (%L) TO (%L)',
            suffix, m_start::TIMESTAMPTZ, m_end::TIMESTAMPTZ
        );
        EXECUTE format(
            'CREATE TABLE blinkit_part.order_items_%s PARTITION OF blinkit_part.order_items_part FOR VALUES FROM (%L) TO (%L)',
            suffix, m_start::TIMESTAMPTZ, m_end::TIMESTAMPTZ
        );
        EXECUTE format(
            'CREATE TABLE blinkit_part.inventory_movements_%s PARTITION OF blinkit_part.inventory_movements_part FOR VALUES FROM (%L) TO (%L)',
            suffix, m_start::TIMESTAMPTZ, m_end::TIMESTAMPTZ
        );

        m_start := m_end;
    END LOOP;
END $$;

CREATE TABLE orders_default PARTITION OF orders_part DEFAULT;
CREATE TABLE order_items_default PARTITION OF order_items_part DEFAULT;
CREATE TABLE inventory_movements_default PARTITION OF inventory_movements_part DEFAULT;

-- Local partitioned indexes (automatically propagated to every child partition)
CREATE INDEX idx_part_orders_placed ON orders_part (placed_at, store_id);
CREATE INDEX idx_part_oi_product_placed ON order_items_part (product_id, placed_at) INCLUDE (quantity_delivered);
CREATE INDEX idx_part_oi_placed_order ON order_items_part (placed_at, order_id) INCLUDE (quantity_ordered, quantity_delivered);

-- Populate from blinkit seed tables to verify pruning on real data
INSERT INTO orders_part
SELECT * FROM blinkit.orders;

INSERT INTO order_items_part (order_id, product_id, placed_at, quantity_ordered, quantity_delivered, unit_price, substitute_product_id)
SELECT oi.order_id, oi.product_id, o.placed_at, oi.quantity_ordered, oi.quantity_delivered, oi.unit_price, oi.substitute_product_id
FROM blinkit.order_items oi
JOIN blinkit.orders o ON o.order_id = oi.order_id;

INSERT INTO inventory_movements_part
SELECT * FROM blinkit.inventory_movements;

ANALYZE orders_part;
ANALYZE order_items_part;
ANALYZE inventory_movements_part;

-- Verify partition pruning with EXPLAIN (ANALYZE, BUFFERS) on June 2026 (R14 equivalent)
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.store_id, count(*) AS lines,
       round(100.0 * count(*) FILTER (WHERE oi.quantity_delivered < oi.quantity_ordered) / count(*), 2) AS short_pct
FROM order_items_part oi
JOIN orders_part o ON o.order_id = oi.order_id AND o.placed_at = oi.placed_at
WHERE o.placed_at  >= '2026-06-01' AND o.placed_at  < '2026-07-01'
  AND oi.placed_at >= '2026-06-01' AND oi.placed_at < '2026-07-01'
GROUP BY o.store_id
ORDER BY short_pct DESC;

