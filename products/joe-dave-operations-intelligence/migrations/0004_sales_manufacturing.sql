-- Joe & Dave sales conversion and manufacturing capacity additions.
ALTER TABLE jd_work_orders ADD COLUMN warehouse_id TEXT REFERENCES jd_warehouses(id);
CREATE TABLE IF NOT EXISTS jd_ops_sales_order_lines (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id),
 sales_order_id TEXT NOT NULL REFERENCES jd_sales_orders(id) ON DELETE CASCADE,
 item_id TEXT REFERENCES jd_items(id), description TEXT NOT NULL,
 quantity REAL NOT NULL CHECK(quantity>0), unit_price_minor INTEGER NOT NULL DEFAULT 0 CHECK(unit_price_minor>=0),
 tax_rate REAL NOT NULL DEFAULT 0 CHECK(tax_rate>=0 AND tax_rate<=100),
 line_subtotal_minor INTEGER NOT NULL DEFAULT 0, line_tax_minor INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS jd_ops_sales_lines_order_idx ON jd_ops_sales_order_lines(business_id,sales_order_id);
CREATE TABLE IF NOT EXISTS jd_work_centers (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id),
 code TEXT NOT NULL, name TEXT NOT NULL, capacity_minutes_per_day INTEGER NOT NULL DEFAULT 480 CHECK(capacity_minutes_per_day>0),
 is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(business_id,code)
);
