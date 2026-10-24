-- Joe & Dave Operations Intelligence: extended business modules
-- Additive migration. Existing records and tables are not dropped or rewritten.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS jd_warehouses (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, code TEXT NOT NULL, name TEXT NOT NULL,
 address TEXT, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(business_id,code)
);
CREATE TABLE IF NOT EXISTS jd_items (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, item_code TEXT NOT NULL, name TEXT NOT NULL,
 description TEXT, item_type TEXT NOT NULL DEFAULT 'stock' CHECK(item_type IN ('stock','service','manufactured','raw_material','finished_good')),
 unit_of_measure TEXT NOT NULL DEFAULT 'unit', tracking_mode TEXT NOT NULL DEFAULT 'none' CHECK(tracking_mode IN ('none','batch','serial')),
 valuation_method TEXT NOT NULL DEFAULT 'moving_average' CHECK(valuation_method IN ('fifo','moving_average')),
 reorder_level REAL NOT NULL DEFAULT 0, reorder_quantity REAL NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,item_code)
);
CREATE TABLE IF NOT EXISTS jd_stock_lots (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES jd_items(id),
 warehouse_id TEXT NOT NULL REFERENCES jd_warehouses(id), lot_code TEXT, serial_number TEXT,
 expiry_date TEXT, quantity_received REAL NOT NULL DEFAULT 0, quantity_remaining REAL NOT NULL DEFAULT 0,
 unit_cost_minor INTEGER NOT NULL DEFAULT 0, received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(quantity_received >= 0), CHECK(quantity_remaining >= 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS jd_stock_serial_unique ON jd_stock_lots(business_id,serial_number) WHERE serial_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS jd_stock_lot_item_wh ON jd_stock_lots(business_id,item_id,warehouse_id,expiry_date);
CREATE TABLE IF NOT EXISTS jd_stock_movements (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES jd_items(id),
 warehouse_id TEXT NOT NULL REFERENCES jd_warehouses(id), lot_id TEXT REFERENCES jd_stock_lots(id),
 movement_type TEXT NOT NULL CHECK(movement_type IN ('opening','receipt','issue','transfer_in','transfer_out','adjustment','production_in','production_out','sale','return')),
 quantity_delta REAL NOT NULL, unit_cost_minor INTEGER NOT NULL DEFAULT 0, reference_type TEXT, reference_id TEXT,
 notes TEXT, actor_user_id TEXT, occurred_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS jd_stock_movement_item_date ON jd_stock_movements(business_id,item_id,occurred_at);
CREATE TABLE IF NOT EXISTS jd_stock_counts (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, warehouse_id TEXT NOT NULL REFERENCES jd_warehouses(id),
 status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','counting','submitted','approved','rejected')),
 count_date TEXT NOT NULL, notes TEXT, created_by TEXT, approved_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS jd_stock_count_lines (
 id TEXT PRIMARY KEY, count_id TEXT NOT NULL REFERENCES jd_stock_counts(id) ON DELETE CASCADE,
 item_id TEXT NOT NULL REFERENCES jd_items(id), system_quantity REAL NOT NULL DEFAULT 0,
 counted_quantity REAL, variance REAL, unit_cost_minor INTEGER NOT NULL DEFAULT 0, notes TEXT,
 UNIQUE(count_id,item_id)
);
CREATE TABLE IF NOT EXISTS jd_crm_leads (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, lead_name TEXT NOT NULL, company_name TEXT,
 email TEXT, phone TEXT, source TEXT, stage TEXT NOT NULL DEFAULT 'new' CHECK(stage IN ('new','qualified','proposal','negotiation','won','lost')),
 estimated_value_minor INTEGER NOT NULL DEFAULT 0, currency_code TEXT NOT NULL DEFAULT 'NGN',
 next_follow_up TEXT, owner_user_id TEXT, notes TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS jd_crm_pipeline ON jd_crm_leads(business_id,stage,next_follow_up);
CREATE TABLE IF NOT EXISTS jd_quotations (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, quote_number TEXT NOT NULL, customer_id TEXT,
 lead_id TEXT REFERENCES jd_crm_leads(id), status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','sent','accepted','rejected','expired','converted')),
 currency_code TEXT NOT NULL DEFAULT 'NGN', subtotal_minor INTEGER NOT NULL DEFAULT 0, tax_minor INTEGER NOT NULL DEFAULT 0,
 total_minor INTEGER NOT NULL DEFAULT 0, valid_until TEXT, created_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(business_id,quote_number)
);
CREATE TABLE IF NOT EXISTS jd_quotation_lines (
 id TEXT PRIMARY KEY, quotation_id TEXT NOT NULL REFERENCES jd_quotations(id) ON DELETE CASCADE,
 item_id TEXT REFERENCES jd_items(id), description TEXT NOT NULL, quantity REAL NOT NULL DEFAULT 1,
 unit_price_minor INTEGER NOT NULL DEFAULT 0, tax_rate REAL NOT NULL DEFAULT 0, line_total_minor INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS jd_sales_orders (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, order_number TEXT NOT NULL, quotation_id TEXT REFERENCES jd_quotations(id),
 customer_id TEXT, status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','confirmed','part_fulfilled','fulfilled','cancelled')),
 currency_code TEXT NOT NULL DEFAULT 'NGN', total_minor INTEGER NOT NULL DEFAULT 0, requested_date TEXT,
 created_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,order_number)
);
CREATE TABLE IF NOT EXISTS jd_suppliers (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, supplier_code TEXT NOT NULL, name TEXT NOT NULL,
 email TEXT, phone TEXT, address TEXT, tax_id TEXT, payment_terms_days INTEGER NOT NULL DEFAULT 0,
 is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,supplier_code)
);
CREATE TABLE IF NOT EXISTS jd_material_requests (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, request_number TEXT NOT NULL, requested_by TEXT,
 department TEXT, required_date TEXT, purpose TEXT, status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','submitted','approved','rejected','ordered','closed')),
 approved_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,request_number)
);
CREATE TABLE IF NOT EXISTS jd_material_request_lines (
 id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES jd_material_requests(id) ON DELETE CASCADE,
 item_id TEXT REFERENCES jd_items(id), description TEXT NOT NULL, quantity REAL NOT NULL CHECK(quantity > 0),
 warehouse_id TEXT REFERENCES jd_warehouses(id)
);
CREATE TABLE IF NOT EXISTS jd_purchase_orders (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, po_number TEXT NOT NULL, supplier_id TEXT NOT NULL REFERENCES jd_suppliers(id),
 request_id TEXT REFERENCES jd_material_requests(id), status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','submitted','approved','sent','part_received','received','cancelled')),
 currency_code TEXT NOT NULL DEFAULT 'NGN', subtotal_minor INTEGER NOT NULL DEFAULT 0, tax_minor INTEGER NOT NULL DEFAULT 0,
 total_minor INTEGER NOT NULL DEFAULT 0, expected_date TEXT, created_by TEXT, approved_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(business_id,po_number)
);
CREATE TABLE IF NOT EXISTS jd_purchase_order_lines (
 id TEXT PRIMARY KEY, purchase_order_id TEXT NOT NULL REFERENCES jd_purchase_orders(id) ON DELETE CASCADE,
 item_id TEXT REFERENCES jd_items(id), description TEXT NOT NULL, quantity_ordered REAL NOT NULL CHECK(quantity_ordered > 0),
 quantity_received REAL NOT NULL DEFAULT 0, unit_cost_minor INTEGER NOT NULL DEFAULT 0, line_total_minor INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS jd_purchase_receipts (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, receipt_number TEXT NOT NULL,
 purchase_order_id TEXT NOT NULL REFERENCES jd_purchase_orders(id), warehouse_id TEXT NOT NULL REFERENCES jd_warehouses(id),
 status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','posted','reversed')), received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 received_by TEXT, notes TEXT, UNIQUE(business_id,receipt_number)
);
CREATE TABLE IF NOT EXISTS jd_purchase_receipt_lines (
 id TEXT PRIMARY KEY, receipt_id TEXT NOT NULL REFERENCES jd_purchase_receipts(id) ON DELETE CASCADE,
 purchase_order_line_id TEXT NOT NULL REFERENCES jd_purchase_order_lines(id), item_id TEXT NOT NULL REFERENCES jd_items(id),
 quantity_received REAL NOT NULL CHECK(quantity_received > 0), unit_cost_minor INTEGER NOT NULL DEFAULT 0, lot_code TEXT, expiry_date TEXT
);
CREATE TABLE IF NOT EXISTS jd_supplier_invoices (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, supplier_id TEXT NOT NULL REFERENCES jd_suppliers(id),
 supplier_invoice_number TEXT NOT NULL, purchase_order_id TEXT REFERENCES jd_purchase_orders(id),
 receipt_id TEXT REFERENCES jd_purchase_receipts(id), invoice_date TEXT, due_date TEXT, currency_code TEXT NOT NULL DEFAULT 'NGN',
 subtotal_minor INTEGER NOT NULL DEFAULT 0, tax_minor INTEGER NOT NULL DEFAULT 0, total_minor INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','matched','exception','approved','paid','void')),
 match_status TEXT NOT NULL DEFAULT 'unmatched' CHECK(match_status IN ('unmatched','matched','variance')),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,supplier_id,supplier_invoice_number)
);
CREATE TABLE IF NOT EXISTS jd_employees (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, employee_number TEXT NOT NULL, first_name TEXT NOT NULL, last_name TEXT NOT NULL,
 email TEXT, phone TEXT, department TEXT, job_title TEXT, employment_type TEXT NOT NULL DEFAULT 'full_time',
 start_date TEXT, end_date TEXT, base_salary_minor INTEGER NOT NULL DEFAULT 0, currency_code TEXT NOT NULL DEFAULT 'NGN',
 bank_name TEXT, bank_account_last4 TEXT, tax_reference TEXT, pension_reference TEXT, status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','on_leave','suspended','exited')),
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,employee_number)
);
CREATE TABLE IF NOT EXISTS jd_attendance (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, employee_id TEXT NOT NULL REFERENCES jd_employees(id),
 work_date TEXT NOT NULL, check_in TEXT, check_out TEXT, status TEXT NOT NULL DEFAULT 'present' CHECK(status IN ('present','absent','late','half_day','remote','leave')),
 minutes_worked INTEGER NOT NULL DEFAULT 0, notes TEXT, approved_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(employee_id,work_date)
);
CREATE TABLE IF NOT EXISTS jd_leave_requests (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, employee_id TEXT NOT NULL REFERENCES jd_employees(id),
 leave_type TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, days REAL NOT NULL CHECK(days > 0),
 reason TEXT, status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','cancelled')),
 requested_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, reviewed_by TEXT, reviewed_at TEXT
);
CREATE TABLE IF NOT EXISTS jd_expense_claims (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, employee_id TEXT NOT NULL REFERENCES jd_employees(id),
 claim_date TEXT NOT NULL, category TEXT NOT NULL, description TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor >= 0),
 currency_code TEXT NOT NULL DEFAULT 'NGN', receipt_reference TEXT, status TEXT NOT NULL DEFAULT 'submitted' CHECK(status IN ('draft','submitted','approved','rejected','paid')),
 approved_by TEXT, paid_at TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS jd_payroll_runs (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, period_start TEXT NOT NULL, period_end TEXT NOT NULL,
 pay_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','calculated','approved','paid','void')),
 currency_code TEXT NOT NULL DEFAULT 'NGN', gross_total_minor INTEGER NOT NULL DEFAULT 0,
 deductions_total_minor INTEGER NOT NULL DEFAULT 0, net_total_minor INTEGER NOT NULL DEFAULT 0,
 created_by TEXT, approved_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,period_start,period_end)
);
CREATE TABLE IF NOT EXISTS jd_payroll_lines (
 id TEXT PRIMARY KEY, payroll_run_id TEXT NOT NULL REFERENCES jd_payroll_runs(id) ON DELETE CASCADE,
 employee_id TEXT NOT NULL REFERENCES jd_employees(id), basic_minor INTEGER NOT NULL DEFAULT 0,
 allowances_minor INTEGER NOT NULL DEFAULT 0, overtime_minor INTEGER NOT NULL DEFAULT 0,
 paye_minor INTEGER NOT NULL DEFAULT 0, pension_minor INTEGER NOT NULL DEFAULT 0, other_deductions_minor INTEGER NOT NULL DEFAULT 0,
 gross_minor INTEGER NOT NULL DEFAULT 0, net_minor INTEGER NOT NULL DEFAULT 0, payslip_reference TEXT,
 UNIQUE(payroll_run_id,employee_id)
);
CREATE TABLE IF NOT EXISTS jd_boms (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, bom_code TEXT NOT NULL, finished_item_id TEXT NOT NULL REFERENCES jd_items(id),
 version INTEGER NOT NULL DEFAULT 1, output_quantity REAL NOT NULL DEFAULT 1, status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','active','obsolete')),
 notes TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,bom_code,version)
);
CREATE TABLE IF NOT EXISTS jd_bom_lines (
 id TEXT PRIMARY KEY, bom_id TEXT NOT NULL REFERENCES jd_boms(id) ON DELETE CASCADE,
 component_item_id TEXT NOT NULL REFERENCES jd_items(id), quantity_per_output REAL NOT NULL CHECK(quantity_per_output > 0),
 scrap_percent REAL NOT NULL DEFAULT 0, operation_sequence INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS jd_work_orders (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, work_order_number TEXT NOT NULL, bom_id TEXT NOT NULL REFERENCES jd_boms(id),
 planned_quantity REAL NOT NULL CHECK(planned_quantity > 0), produced_quantity REAL NOT NULL DEFAULT 0,
 planned_start TEXT, planned_end TEXT, actual_start TEXT, actual_end TEXT,
 status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','released','in_progress','paused','completed','cancelled')),
 priority TEXT NOT NULL DEFAULT 'normal', work_center TEXT, created_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(business_id,work_order_number)
);
CREATE TABLE IF NOT EXISTS jd_job_cards (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, work_order_id TEXT NOT NULL REFERENCES jd_work_orders(id),
 card_number TEXT NOT NULL, operation_name TEXT NOT NULL, sequence_no INTEGER NOT NULL DEFAULT 1,
 assigned_to TEXT, planned_minutes INTEGER NOT NULL DEFAULT 0, actual_minutes INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','ready','in_progress','blocked','done','rework')),
 started_at TEXT, completed_at TEXT, notes TEXT, UNIQUE(business_id,card_number)
);
CREATE TABLE IF NOT EXISTS jd_projects (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, project_code TEXT NOT NULL, name TEXT NOT NULL, customer_id TEXT,
 description TEXT, start_date TEXT, end_date TEXT, budget_minor INTEGER NOT NULL DEFAULT 0,
 currency_code TEXT NOT NULL DEFAULT 'NGN', billing_method TEXT NOT NULL DEFAULT 'fixed' CHECK(billing_method IN ('fixed','time_materials','non_billable')),
 hourly_rate_minor INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','active','on_hold','completed','cancelled')),
 owner_user_id TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,project_code)
);
CREATE TABLE IF NOT EXISTS jd_tasks (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, project_id TEXT NOT NULL REFERENCES jd_projects(id) ON DELETE CASCADE,
 parent_task_id TEXT REFERENCES jd_tasks(id), title TEXT NOT NULL, description TEXT, assigned_to TEXT,
 status TEXT NOT NULL DEFAULT 'todo' CHECK(status IN ('todo','in_progress','blocked','done','cancelled')),
 priority TEXT NOT NULL DEFAULT 'normal', planned_start TEXT, due_date TEXT, completed_at TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS jd_task_dependencies (
 task_id TEXT NOT NULL REFERENCES jd_tasks(id) ON DELETE CASCADE, depends_on_task_id TEXT NOT NULL REFERENCES jd_tasks(id) ON DELETE CASCADE,
 PRIMARY KEY(task_id,depends_on_task_id), CHECK(task_id <> depends_on_task_id)
);
CREATE TABLE IF NOT EXISTS jd_timesheets (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, employee_id TEXT NOT NULL REFERENCES jd_employees(id),
 project_id TEXT NOT NULL REFERENCES jd_projects(id), task_id TEXT REFERENCES jd_tasks(id),
 work_date TEXT NOT NULL, minutes_logged INTEGER NOT NULL CHECK(minutes_logged > 0),
 billable INTEGER NOT NULL DEFAULT 1, hourly_rate_minor INTEGER NOT NULL DEFAULT 0,
 notes TEXT, status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','submitted','approved','rejected','invoiced')),
 approved_by TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS jd_support_tickets (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, ticket_number TEXT NOT NULL, customer_id TEXT,
 subject TEXT NOT NULL, description TEXT NOT NULL, category TEXT, priority TEXT NOT NULL DEFAULT 'normal' CHECK(priority IN ('low','normal','high','urgent')),
 status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','in_progress','waiting_customer','resolved','closed')),
 assigned_to TEXT, sla_due_at TEXT, first_response_at TEXT, resolved_at TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(business_id,ticket_number)
);
CREATE TABLE IF NOT EXISTS jd_ticket_messages (
 id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES jd_support_tickets(id) ON DELETE CASCADE,
 author_user_id TEXT, message TEXT NOT NULL, is_internal INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS jd_knowledge_articles (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, slug TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
 category TEXT, visibility TEXT NOT NULL DEFAULT 'internal' CHECK(visibility IN ('internal','customer','public')),
 status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','archived')),
 author_user_id TEXT, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(business_id,slug)
);
CREATE TABLE IF NOT EXISTS jd_audit_events (
 id TEXT PRIMARY KEY, business_id TEXT NOT NULL, actor_user_id TEXT, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
 action TEXT NOT NULL, before_json TEXT, after_json TEXT, reason TEXT, occurred_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS jd_audit_entity ON jd_audit_events(business_id,entity_type,entity_id,created_at);
