-- Joe&dave Operations Intelligence — Cloudflare D1 schema
-- Fresh-install migration. No sample businesses, users, invoices, or balances are seeded.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS jd_users (
 id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE COLLATE NOCASE, password_hash TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE IF NOT EXISTS jd_businesses (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES jd_users(id), legal_name TEXT NOT NULL,
 display_name TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT 'NGN',
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE IF NOT EXISTS jd_customers (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id), name TEXT NOT NULL,
 email TEXT, phone TEXT, address TEXT, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS jd_customers_business_idx ON jd_customers(business_id);
CREATE TABLE IF NOT EXISTS jd_inventory_items (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id), sku TEXT, name TEXT NOT NULL,
 unit TEXT NOT NULL DEFAULT 'pcs', quantity REAL NOT NULL DEFAULT 0 CHECK(quantity>=0),
 reorder_level REAL NOT NULL DEFAULT 0 CHECK(reorder_level>=0), cost_minor INTEGER NOT NULL DEFAULT 0 CHECK(cost_minor>=0),
 sale_price_minor INTEGER NOT NULL DEFAULT 0 CHECK(sale_price_minor>=0), warehouse TEXT NOT NULL DEFAULT 'Main',
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), UNIQUE(business_id,sku)
);
CREATE TABLE IF NOT EXISTS jd_invoices (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id), customer_id TEXT REFERENCES jd_customers(id),
 invoice_number TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','issued','part_paid','paid','void')),
 issue_date TEXT NOT NULL, due_date TEXT, subtotal_minor INTEGER NOT NULL DEFAULT 0 CHECK(subtotal_minor>=0),
 tax_minor INTEGER NOT NULL DEFAULT 0 CHECK(tax_minor>=0), total_minor INTEGER NOT NULL DEFAULT 0 CHECK(total_minor>=0),
 paid_minor INTEGER NOT NULL DEFAULT 0 CHECK(paid_minor>=0), notes TEXT,
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), UNIQUE(business_id,invoice_number)
);
CREATE TABLE IF NOT EXISTS jd_invoice_lines (
 id TEXT PRIMARY KEY, invoice_id TEXT NOT NULL REFERENCES jd_invoices(id) ON DELETE CASCADE, description TEXT NOT NULL,
 quantity REAL NOT NULL CHECK(quantity>0), unit_price_minor INTEGER NOT NULL CHECK(unit_price_minor>=0),
 tax_rate REAL NOT NULL DEFAULT 0 CHECK(tax_rate>=0 AND tax_rate<=100), line_subtotal_minor INTEGER NOT NULL, line_tax_minor INTEGER NOT NULL,
 item_id TEXT REFERENCES jd_inventory_items(id), unit_cost_minor INTEGER NOT NULL DEFAULT 0 CHECK(unit_cost_minor>=0), cost_total_minor INTEGER NOT NULL DEFAULT 0 CHECK(cost_total_minor>=0)
);
CREATE TABLE IF NOT EXISTS jd_receipts (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id), invoice_id TEXT NOT NULL REFERENCES jd_invoices(id),
 amount_minor INTEGER NOT NULL CHECK(amount_minor>0), payment_method TEXT NOT NULL, reference TEXT,
 received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), notes TEXT
);
CREATE TABLE IF NOT EXISTS jd_stock_movements (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id), item_id TEXT NOT NULL REFERENCES jd_inventory_items(id),
 movement_type TEXT NOT NULL CHECK(movement_type IN ('opening','purchase','sale','adjustment','return')),
 quantity_delta REAL NOT NULL CHECK(quantity_delta<>0), reference TEXT,
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE IF NOT EXISTS jd_audit_events (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL REFERENCES jd_businesses(id), actor_id TEXT REFERENCES jd_users(id),
 action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT, details_json TEXT NOT NULL DEFAULT '{}',
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TABLE IF NOT EXISTS jd_sessions (
 token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES jd_users(id) ON DELETE CASCADE, expires_at TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE TRIGGER IF NOT EXISTS jd_invoice_line_insert AFTER INSERT ON jd_invoice_lines BEGIN
 UPDATE jd_invoices SET subtotal_minor=(SELECT COALESCE(SUM(line_subtotal_minor),0) FROM jd_invoice_lines WHERE invoice_id=NEW.invoice_id),
 tax_minor=(SELECT COALESCE(SUM(line_tax_minor),0) FROM jd_invoice_lines WHERE invoice_id=NEW.invoice_id),
 total_minor=(SELECT COALESCE(SUM(line_subtotal_minor+line_tax_minor),0) FROM jd_invoice_lines WHERE invoice_id=NEW.invoice_id) WHERE id=NEW.invoice_id;
END;
CREATE TRIGGER IF NOT EXISTS jd_invoice_line_update AFTER UPDATE ON jd_invoice_lines BEGIN
 UPDATE jd_invoices SET subtotal_minor=(SELECT COALESCE(SUM(line_subtotal_minor),0) FROM jd_invoice_lines WHERE invoice_id=NEW.invoice_id),
 tax_minor=(SELECT COALESCE(SUM(line_tax_minor),0) FROM jd_invoice_lines WHERE invoice_id=NEW.invoice_id),
 total_minor=(SELECT COALESCE(SUM(line_subtotal_minor+line_tax_minor),0) FROM jd_invoice_lines WHERE invoice_id=NEW.invoice_id) WHERE id=NEW.invoice_id;
END;
CREATE TRIGGER IF NOT EXISTS jd_invoice_line_delete AFTER DELETE ON jd_invoice_lines BEGIN
 UPDATE jd_invoices SET subtotal_minor=(SELECT COALESCE(SUM(line_subtotal_minor),0) FROM jd_invoice_lines WHERE invoice_id=OLD.invoice_id),
 tax_minor=(SELECT COALESCE(SUM(line_tax_minor),0) FROM jd_invoice_lines WHERE invoice_id=OLD.invoice_id),
 total_minor=(SELECT COALESCE(SUM(line_subtotal_minor+line_tax_minor),0) FROM jd_invoice_lines WHERE invoice_id=OLD.invoice_id) WHERE id=OLD.invoice_id;
END;
CREATE TRIGGER IF NOT EXISTS jd_receipt_insert AFTER INSERT ON jd_receipts BEGIN
 UPDATE jd_invoices SET paid_minor=(SELECT COALESCE(SUM(amount_minor),0) FROM jd_receipts WHERE invoice_id=NEW.invoice_id),
 status=CASE WHEN (SELECT COALESCE(SUM(amount_minor),0) FROM jd_receipts WHERE invoice_id=NEW.invoice_id)>=total_minor THEN 'paid'
 WHEN (SELECT COALESCE(SUM(amount_minor),0) FROM jd_receipts WHERE invoice_id=NEW.invoice_id)>0 THEN 'part_paid' ELSE status END WHERE id=NEW.invoice_id;
END;
CREATE TRIGGER IF NOT EXISTS jd_stock_insert AFTER INSERT ON jd_stock_movements BEGIN
 UPDATE jd_inventory_items SET quantity=quantity+NEW.quantity_delta WHERE id=NEW.item_id AND quantity+NEW.quantity_delta>=0;
END;
CREATE VIEW IF NOT EXISTS jd_business_summary AS
 SELECT b.id AS business_id,b.display_name,b.currency_code,
 (SELECT COUNT(*) FROM jd_invoices i WHERE i.business_id=b.id AND i.status<>'void') AS invoice_count,
 (SELECT COALESCE(SUM(total_minor),0) FROM jd_invoices i WHERE i.business_id=b.id AND i.status<>'void') AS invoiced_minor,
 (SELECT COALESCE(SUM(paid_minor),0) FROM jd_invoices i WHERE i.business_id=b.id AND i.status<>'void') AS collected_minor,
 (SELECT COUNT(*) FROM jd_inventory_items x WHERE x.business_id=b.id AND x.quantity<=x.reorder_level) AS low_stock_count
 FROM jd_businesses b;
