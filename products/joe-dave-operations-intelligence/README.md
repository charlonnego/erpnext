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

## Current status

This file establishes the product boundary and working rules. It does not claim that legacy UI code has already been migrated, that production has been switched, or that all workflows are complete. Production cutover must wait for an independent application entry point, API/schema ownership, automated tests, and verified deployment.
