# Joe&dave Operations Intelligence — implementation plan

## Product goal

Add a practical, permission-aware operations intelligence layer to the Joe&dave product, built on this modified ERPNext codebase, for service businesses. The underlying ERPNext records remain the system of record; this feature summarizes existing transactions and helps owners decide what to do next. Keep upstream attribution and license notices intact; see [Joe&dave branding and open-source compliance](../JOE_AND_DAVE_COMPLIANCE.md).

## First vertical slice: owner overview

Deliver a server-side KPI endpoint for the active user's default company:
- Submitted sales value for a selected date range.
- Submitted purchase value for the same date range.
- Outstanding customer receivables and count of overdue sales invoices.
- Outstanding supplier payables.
- A clear date range and company in the response.

The first release deliberately uses deterministic calculations, existing ERPNext documents, and Frappe's permission-aware list APIs. It must not invent data, write accounting entries, or make financial decisions automatically.

## Next increments

1. Action centre: **initial slice implemented** for overdue submitted sales and purchase invoices. It lists up to 10 permission-visible items, ordered by due date, and opens the source invoice. Low-stock items, delayed projects/tasks and pending approvals remain future work.
2. Inventory signals: **initial low-stock slice implemented** using warehouse-specific Item reorder levels and visible Bin actual quantities. Slow-moving stock and deeper stock-ledger analysis remain future work; verify against warehouse permissions and stock UOMs in a live site.
3. Service profitability: project/service revenue and cost where source data supports it; label estimates and missing costs.
4. Trends and anomaly rules: compare consistent periods, explain each rule, and avoid false precision.
5. AI business adviser: optional natural-language explanations grounded only in permission-filtered metrics; no autonomous posting, payment, refunds or stock adjustments.
6. Mobile and offline: responsive web first; then a dedicated Android/PWA workflow for offline capture with idempotency keys, retry-safe sync, and explicit conflict resolution.

## Engineering guardrails

- Do not modify upstream accounting semantics or silently change ERPNext core workflows.
- Read through Frappe permission-aware APIs; never expose another user's/company's records.
- Use submitted documents (docstatus = 1) for financial KPIs and state the metric definitions.
- Validate date ranges and require a default company.
- No fabricated demo values in production responses.
- Add automated tests for date validation, no-company behavior, aggregation, permissions, and empty datasets.
- Keep this feature isolated so it can later become a separate Frappe app if that is safer for upgrades.

## Acceptance criteria for the first slice

- Endpoint returns stable JSON with company, from/to dates and named metrics.
- Draft/cancelled invoices are excluded.
- The result is limited to the active user's default company and permissions.
- Invalid or reversed date ranges fail with a useful validation message.
- Empty accounts return zero values rather than errors.
- No writes are performed.
