# Joe&dave Operations Intelligence — Cloudflare runtime

This is an independent application, not a Frappe/ERPNext runtime or fork. The public UI is deployed on Cloudflare Pages; authenticated business logic runs in Cloudflare Workers; records are stored in a dedicated Cloudflare D1 database.

## Runtime resources
- Pages project: `joe-dave-operations-intelligence`
- API Worker: `joe-dave-operations-api`
- D1 database: `joe-dave-operations`
- API origin: `https://joe-dave-operations-api.uchechukwuanuforo.workers.dev`
- D1 binding: `DB`

## Migration
`migrations/0001_joe_dave_core.sql` describes the fresh-install schema. The live D1 database was provisioned from the same core schema and includes the `warehouse` column on inventory items. It contains no seeded demo users, customers, invoices, receipts, or inventory records.

## Implemented API
- `GET /health`
- `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`
- `GET /business`, `PUT /business`
- `GET/POST /customers`
- `GET/POST /invoices`
- `POST /invoices/:id/receipts`
- `GET/POST /inventory`, `POST /inventory/import`
- `GET /dashboard`

Authentication uses PBKDF2 password hashes, random bearer tokens whose SHA-256 hashes are stored in D1, expiry checks, and business-owner scoping on data reads/writes. The browser holds the session token in tab-scoped session storage. The Worker applies an origin allowlist for the Pages domain family.

## Current engineering status
- Per-business invoice counters replace count-based invoice numbering.
- Invoice posting, receipts, and expenses create balanced journal entries; trial balance, profit/loss and audit endpoints are available.
- Stock opening balances and CSV imports write stock movement records; database guards prevent negative stock and over-receipting.
- Login attempts are throttled by hashed email/IP identifiers; passwords use PBKDF2 and session token hashes are stored instead of raw tokens.

The deployed Worker source is version-controlled at `cloudflare/worker.js`; `cloudflare/wrangler.toml` defines the Worker and D1 binding. `cloudflare/tests/smoke.mjs` and `.github/workflows/cloudflare-api-smoke.yml` provide live boundary checks and module syntax validation.

## Important production hardening still required
This is an active presentation/MVP build, not yet a substitute for a mature ERP. Before handling sensitive or high-volume business operations, add email verification and password reset, production-grade rate limiting/bot protection, stronger session revocation/rotation, credit notes/refunds, inventory valuation/COGS accounting, purchase-order-to-bill three-way matching, bank-statement CSV parsing and reconciliation exception handling, exports/backup restore drills, monitoring/alerting, multi-user roles/permissions, automated end-to-end tests, and an independent security review. Cloudflare Free quotas apply.
