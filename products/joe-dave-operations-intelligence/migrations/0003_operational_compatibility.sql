-- Joe & Dave operational module compatibility migration.
-- Additive only: retain existing accounting/inventory data and legacy table contracts.
ALTER TABLE jd_suppliers ADD COLUMN supplier_code TEXT;
ALTER TABLE jd_suppliers ADD COLUMN payment_terms_days INTEGER NOT NULL DEFAULT 0;
ALTER TABLE jd_suppliers ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1;
ALTER TABLE jd_ticket_messages ADD COLUMN business_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS jd_ops_supplier_code_unique ON jd_suppliers(business_id,supplier_code) WHERE supplier_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS jd_ticket_messages_tenant_idx ON jd_ticket_messages(business_id,ticket_id,created_at);
CREATE TABLE IF NOT EXISTS jd_ops_stock_movements (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id), item_id TEXT NOT NULL REFERENCES jd_items(id),
 warehouse_id TEXT NOT NULL REFERENCES jd_warehouses(id), lot_id TEXT REFERENCES jd_stock_lots(id),
 movement_type TEXT NOT NULL CHECK(movement_type IN ('opening','receipt','issue','transfer_in','transfer_out','adjustment','production_in','production_out','sale','return')),
 quantity_delta REAL NOT NULL CHECK(quantity_delta<>0), unit_cost_minor INTEGER NOT NULL DEFAULT 0 CHECK(unit_cost_minor>=0),
 reference_type TEXT, reference_id TEXT, notes TEXT, actor_user_id TEXT REFERENCES jd_users(id),
 occurred_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS jd_ops_stock_item_wh_date ON jd_ops_stock_movements(business_id,item_id,warehouse_id,occurred_at);
CREATE TABLE IF NOT EXISTS jd_ops_purchase_order_lines (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id),
 purchase_order_id TEXT NOT NULL REFERENCES jd_purchase_orders(id), item_id TEXT NOT NULL REFERENCES jd_items(id),
 description TEXT NOT NULL, quantity_ordered REAL NOT NULL CHECK(quantity_ordered>0),
 quantity_received REAL NOT NULL DEFAULT 0 CHECK(quantity_received>=0), unit_cost_minor INTEGER NOT NULL DEFAULT 0 CHECK(unit_cost_minor>=0),
 line_total_minor INTEGER NOT NULL DEFAULT 0 CHECK(line_total_minor>=0)
);
CREATE INDEX IF NOT EXISTS jd_ops_po_lines_order_idx ON jd_ops_purchase_order_lines(business_id,purchase_order_id);
CREATE TABLE IF NOT EXISTS jd_ops_purchase_receipt_lines (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id),
 receipt_id TEXT NOT NULL REFERENCES jd_purchase_receipts(id) ON DELETE CASCADE,
 purchase_order_line_id TEXT NOT NULL REFERENCES jd_ops_purchase_order_lines(id),
 item_id TEXT NOT NULL REFERENCES jd_items(id), quantity_received REAL NOT NULL CHECK(quantity_received>0),
 unit_cost_minor INTEGER NOT NULL DEFAULT 0 CHECK(unit_cost_minor>=0), lot_code TEXT, serial_number TEXT, expiry_date TEXT
);
CREATE INDEX IF NOT EXISTS jd_ops_receipt_lines_idx ON jd_ops_purchase_receipt_lines(business_id,receipt_id);
