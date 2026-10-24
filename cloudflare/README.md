# Joe&dave Operations Intelligence — Cloudflare runtime

Independent custom application. Frappe/ERPNext is not a runtime dependency.

## Runtime resources
- Cloudflare Pages project: `joe-dave-operations-intelligence`
- API Worker: `joe-dave-operations-api`
- Dedicated D1 database: `joe-dave-operations`
- API origin: `https://joe-dave-operations-api.uchechukwuanuforo.workers.dev`
- Worker D1 binding: `DB`

## Versioned deployment assets
- `worker.js`: deployed Worker source
- `wrangler.toml`: Worker deployment and D1 binding
- `d1/migrations/0001_joe_dave_core.sql`: business, customers, invoices, receipts, inventory, audit and sessions
- `d1/migrations/0002_accounting_inventory_controls.sql`: suppliers, expenses, purchase orders, journal ledger, auth attempts, stock/receipt/receiving guards
- `d1/migrations/0003_payables_periods_banking.sql`: supplier bills/payments, period locks and bank reconciliation tables/guards
- `d1/migrations/0004_branding_templates.sql`: business contact details, compact logo data URL, brand colour and invoice/receipt template preferences
- `tests/smoke.mjs`: live health/auth/CORS smoke tests
- `tests/frontend.test.mjs`: inline JS syntax, navigation and API wiring checks
- `../.github/workflows/cloudflare-api-smoke.yml`: automated checks

**Existing database migration note:** the live D1 schema was provisioned directly through the Cloudflare API before Wrangler migration tracking was initialized. Do not run `wrangler d1 migrations apply` against the live database until its baseline is reconciled, because the existing columns and triggers are already present. The database contains no seeded demo users, customers, invoices, receipts, or inventory records.

## API routes

- Health: `GET /health`
- Authentication: `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`
- Business: `GET /business`, `PUT /business`
- Dashboard: `GET /dashboard`
- Data analysis: `GET /analytics` (12-month invoicing, receipt collections, recorded expenses, expense categories, top customers and recorded-cost gross profit)
- Customers: `GET/POST /customers`
- Suppliers: `GET/POST /suppliers`
- Invoices and receipts: `GET/POST /invoices`, `GET /invoices/:id`, `GET /receipts`, `POST /invoices/:id/receipts`
- Business identity and documents: `GET/PUT /business` supports logo, contact details, accent colour, and invoice/receipt template preferences. The UI exports invoice/receipt PDFs through the browser print dialog and renders JPG files locally.
- Inventory: `GET/POST /inventory`, `POST /inventory/import`, `GET/POST /inventory/movements`
- Purchasing: `GET/POST /purchase-orders`, `GET /purchase-orders/:id`, `POST /purchase-orders/:id/receive`
- Expenses: `GET/POST /expenses`
- Supplier payables: `GET/POST /supplier-bills`, `POST /supplier-bills/:id/payments`
- Accounting: `GET /journal`, `GET /reports/trial-balance`, `GET /reports/profit-loss?from=YYYY-MM-DD&to=YYYY-MM-DD`, `GET /reports/inventory-valuation`, `GET /reports/audit`
- Periods: `GET/POST /accounting-periods`
- Banking: `GET/POST /bank-accounts`, `POST /bank-transactions/import`, `GET /bank-transactions`, `POST /bank-transactions/:id/reconcile`

## Security and accounting controls
- Passwords use PBKDF2-HMAC-SHA-256 with 210,000 iterations and a random salt.
- Random 256-bit bearer session tokens are held in tab-scoped session storage; only SHA-256 token hashes are stored in D1. Sessions expire after seven days.
- Reads and writes are scoped to the authenticated owner's business.
- Login attempts are throttled using hashed email/IP identifiers; CORS rejects untrusted origins.
- Invoice and purchase-order numbers use per-business counters.
- Invoice posting, receipts, expenses, supplier bills and supplier payments create balanced journal entries. Receipt/payable triggers prevent overpayment.
- Inventory opening balances, imports and purchase receiving create stock movements; database triggers prevent negative stock and over-receiving.
- Closed periods reject new invoices, expenses, bills, receipts, payments and journal postings.
- Logo images are restricted to PNG/JPEG/WebP under 90 KB and stored as a validated data URL in D1 for this $0 presentation build. Move logos to object storage if uploads or usage grow.
- No sample financial records are seeded. Cloudflare Free quotas apply.

## Production release gates still outstanding
This is a functional MVP/presentation build, not yet feature-equivalent to a mature ERP and not yet ready for statutory or high-value accounting without further work. Outstanding items include email verification and password reset, stronger managed rate limiting/bot protection and session revocation, credit notes/refunds, inventory COGS accounting and valuation layers, purchase-order-to-bill three-way matching, bank statement CSV import and reconciliation exceptions, backup/restore drills, monitoring/alerts, multi-user roles and permissions, comprehensive end-to-end write tests, jurisdiction-specific tax controls, and independent security review.
