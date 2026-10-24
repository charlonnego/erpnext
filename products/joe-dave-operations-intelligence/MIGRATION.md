# Application migration

The existing operational interface has been moved into this product-owned directory and is now the standalone application entry point. The old demo directory is no longer the configured Pages root.

## Preserved operational areas

- Authentication and workspace selection/membership
- Customers, invoices, receipts and supplier bills
- Inventory, purchasing and supplier records
- Expenses and financial reports
- Bank accounts, bank transactions and reconciliation
- Journals, accounting periods, SaaS plan/period status and analytics
- Existing API-driven workflow actions and live-record empty states

## Deployment

Cloudflare Pages is configured to use this directory as its root and only deploy when files under this product directory change. The API Worker and D1 database are preserved. The product still uses the repository hosting it; the application itself has no Frappe or ERPNext runtime dependency.

## Verification status

Inline JavaScript syntax was checked after migration. A successful Pages deployment and authenticated end-to-end verification must be confirmed separately; neither should be inferred from a commit alone.
