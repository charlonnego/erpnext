# Joe&dave Operations Intelligence

An independent business operations SaaS product. This directory is the product-owned source boundary; it is not an ERPNext app, theme, plugin, or runtime.

## Product rules

- Own application code, API contracts, schema migrations, tests, and release documentation here.
- Do not use or deploy `docs/operations_intelligence/demo/` as the production application.
- No dependency on ERPNext/Frappe runtime, assets, database, or APIs.
- All business records and metrics must come from authenticated, tenant-scoped API/database queries. Never seed demonstration transactions or display fabricated KPIs.
- Every mutating control must call a real API operation, show a truthful result, and refresh persisted state.
- Financial totals must be derived from persisted records with documented currency/minor-unit rules.
- Enforce workspace membership and role authorization server-side on every read and write.
- Maintain the $0 deployment constraint: do not enable paid services or upgrade plans without explicit approval.

## Operational modules status (2026-10-24)

The seven operational areas now have dedicated authenticated UI workspaces and tenant-scoped Worker API routes:

- **Inventory:** item masters, warehouses, batch/serial lots, stock movements, stock counts and approval adjustments, stock valuation/reorder summaries, and draft reorder purchase orders.
- **Selling & CRM:** lead pipeline, quotations with line items, quote acceptance and conversion to sales orders.
- **Buying:** supplier records, material requests and lines, purchase orders and lines, receipt posting into stock, and supplier invoice matching against the order and posted receipt.
- **HR & Payroll:** employee records, attendance, leave and expense claims with approval controls, payroll runs, base-salary calculations and salary-slip records.
- **Manufacturing:** BOM component lines, multi-level BOM material explosion, work orders, material issue and finished-goods receipt, job cards, work centres and a capacity summary.
- **Projects:** projects, tasks, dependency cycle checks, timesheets, project-costing summaries, and draft customer invoice generation from approved billable time.
- **Helpdesk:** tickets, ticket messages, knowledge-base articles, and overdue SLA reporting.

The live schema includes additive migrations 0002 through 0005. Existing finance tables are preserved; compatibility tables are used where the original schema has a different shape. No demonstration business records were seeded.

## Release limits and safeguards

- Payroll currently calculates **base salary only**. PAYE, pension, statutory deductions, tax compliance and bank-file/payment integration must be configured and independently validated before real payroll runs.
- Manufacturing costing currently captures material cost; labour/overhead costing and automated child work-order scheduling for subassemblies are not complete.
- Timesheet billing creates a **draft** invoice for review; it does not issue invoices or post accounting journals automatically.
- Automated reorder creates a **draft** purchase order requiring review, not an automatically sent supplier order.
- The UI and Worker JavaScript syntax are checked in the Joe & Dave operational workflow. Cloudflare deployment success confirms publication, not a full authenticated browser-based end-to-end acceptance test.

Never represent these limitations as completed capabilities. Keep all customer-facing claims aligned with the workflows that have been tested.
