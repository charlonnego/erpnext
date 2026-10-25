-- Joe&dave Operations Intelligence — D1 migration 0004
-- Capture item linkage and cost snapshots on invoice lines for inventory/COGS accounting.
ALTER TABLE jd_invoice_lines ADD COLUMN item_id TEXT REFERENCES jd_inventory_items(id);
ALTER TABLE jd_invoice_lines ADD COLUMN unit_cost_minor INTEGER NOT NULL DEFAULT 0 CHECK(unit_cost_minor>=0);
ALTER TABLE jd_invoice_lines ADD COLUMN cost_total_minor INTEGER NOT NULL DEFAULT 0 CHECK(cost_total_minor>=0);
