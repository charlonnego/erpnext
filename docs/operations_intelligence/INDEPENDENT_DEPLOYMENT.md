# Joe&dave Operations Intelligence — standalone SaaS deployment

## Product boundary

Joe&dave Operations Intelligence is a standalone business-management SaaS. Its production application is the Cloudflare Pages frontend in `cloudflare/site/`, the Cloudflare Worker API in `cloudflare/worker.js`, and the dedicated Cloudflare D1 database. It must not require an installed ERPNext/Frappe instance, import ERPNext modules, or read/write another company's ERPNext database.

The repository name and legacy ERPNext source elsewhere in this repository are historical baggage, not a runtime dependency. The standalone application must be developed, tested, deployed, and described as its own product. Do not call its frontend a demo.

## Runtime architecture

- **Frontend:** Cloudflare Pages; source directory and static build output: `cloudflare/site`.
- **API:** Cloudflare Worker `joe-dave-operations-api`.
- **Database:** dedicated D1 database bound as `DB`.
- **Identity and access:** API-managed sessions, workspace memberships, and server-side role checks.
- **Business records:** customers, invoices, receipts, inventory, suppliers, expenses, purchasing, payables, periods, banking, journal/report endpoints, and audit records use the standalone API and database.
- **No ERPNext runtime:** no Frappe site, ERPNext server, MariaDB, Redis, or ERPNext credentials are required by this SaaS.
- **Billing:** payment provider and paid subscription lifecycle are not yet enabled; do not present the Pilot workspace status as a paid subscription.

## Deployment

1. Deploy `cloudflare/site` as the Cloudflare Pages build output.
2. Deploy `cloudflare/worker.js` to the `joe-dave-operations-api` Worker with the `DB` D1 binding.
3. Apply only reviewed, versioned D1 schema changes. The live database was originally provisioned directly through the Cloudflare API before Wrangler migration tracking was initialized; reconcile its baseline before using migration automation against production.
4. Keep secrets in Cloudflare environment/secret settings, never in source control.
5. Verify health, anonymous rejection, authenticated access, workspace membership boundaries, and actual create/read/update workflows against real authorized accounts before calling a release production-ready.
6. Do not seed sample customers, invoices, receipts, expenses, suppliers, inventory, or other pretend business transactions. Empty states must honestly report that there are no records.
7. Back up the D1 database and document a tested recovery process before onboarding paying businesses.

## Scope and release honesty

This is an independent SaaS architecture, not a claim of complete ERPNext feature parity or certified accounting compliance. Subscription billing, authenticated multi-tenant end-to-end tests, financial posting/reconciliation review, and backup/restore verification remain release gates. Do not advertise those as completed until they have actually passed.
