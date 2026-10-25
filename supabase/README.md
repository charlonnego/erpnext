# Joe&dave Operations Intelligence — independent engine

This directory is the start of the independent application backend. It is **not** a Frappe or ERPNext extension.

## Zero-budget target architecture

- **Frontend:** the Joe&dave web client deployed on Cloudflare Pages.
- **Identity and PostgreSQL:** a dedicated Supabase project on its Free plan during development.
- **Business engine:** PostgreSQL constraints, transactional triggers and application code owned by Joe&dave.
- **Future migration:** PostgreSQL-compatible AWS services and a separately hosted application/API, using exportable schema and data.

Do not reuse the Kaimacoin, Swiftly, Charley or any other existing project database. Joe&dave must have its own project and isolated records.

## Current status

- [x] Initial standalone schema authored.
- [x] Owner-scoped row-level security policies added to business tables.
- [x] Invoice line totals and receipt allocation recalculation implemented transactionally.
- [x] Stock movement ledger is append-only for authenticated clients.
- [ ] Dedicated Joe&dave Supabase project created and schema applied.
- [ ] Authenticated client connected to the Pages frontend.
- [ ] End-to-end tests for customer, invoice, receipt, stock import and dashboard calculations.
- [ ] Deployment verification against real saved records.

No live backend is connected merely by adding this source file. Do not advertise the app as production-ready until the unchecked items are completed and verified.

## Database

Apply `migrations/202610240001_joe_dave_core.sql` only to a new, dedicated Joe&dave Supabase project. It creates owner-isolated business records for customers, invoices, invoice lines, receipts, inventory items, stock movements and audit events.

The browser may contain only the Supabase project URL and publishable key. Never put a service-role/secret key in Cloudflare Pages frontend code.

## Financial integrity and next steps

The schema has basic data constraints and transactional recalculation triggers. Before real financial use, implement and test:
- business setup and membership/role management;
- safe invoice numbering and issue/void rules;
- receipt allocation, reversal/refund and overpayment edge cases;
- inventory CSV parsing and a single transactional import API;
- stock movement reversal and concurrency safeguards;
- audit coverage, backups/export, tax/rounding rules and accounting reports;
- authenticated end-to-end tests and security review.

This is a development foundation, not a claim of audited accounting software.