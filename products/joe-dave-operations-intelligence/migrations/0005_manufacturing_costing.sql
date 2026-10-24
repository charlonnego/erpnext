-- Manufacturing costing support.
ALTER TABLE jd_work_orders ADD COLUMN material_cost_minor INTEGER NOT NULL DEFAULT 0;
