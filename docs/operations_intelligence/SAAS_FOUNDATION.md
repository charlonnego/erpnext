# Joe&dave SaaS foundation and verification

## Current architecture

- Frontend: Cloudflare Pages at joe-dave-operations-intelligence.pages.dev.
- API: Cloudflare Worker joe-dave-operations-api.
- Database: Cloudflare D1 joe-dave-operations.
- No Frappe/ERPNext runtime dependency.
- No payment provider is connected. The API deliberately reports billing_enabled: false.
- New workspaces are marked as pilot; this is a product state, not a paid subscription.

## Tenant model

Migration 0005_saas_tenancy_foundation.sql adds:
- jd_business_memberships: a user can belong to a business with a role.
- jd_sessions.business_id: each session is scoped to one active workspace.
- jd_business_subscriptions: plan/status metadata without collecting payments.
- A database guard that prevents removing or demoting the final business owner.

Existing business owners and sessions are backfilled. No sample business, invoice, customer, receipt or expense records are created.

## Roles

- Owner: full access; the database prevents removal/demotion of the last owner.
- Administrator: full workspace access except that an owner remains protected.
- Accountant: financial and reporting access; no branding edits or team management.
- Sales: customer, invoice and receipt workflows.
- Inventory: stock and purchasing workflows.
- Viewer: read-only API access.

The Worker enforces roles on the server; hiding a UI control is not considered authorization. Review the role allowlist when adding any new API route.

## Team and workspace API

- GET /workspace/list: list only the authenticated user's memberships.
- POST /workspace/switch: switch a session only to a workspace the user belongs to.
- GET /workspace/members: owner/admin team listing.
- POST /workspace/members: owner/admin adds an already registered user and role.
- DELETE /workspace/members/:userId: owner/admin removes a non-owner member.
- GET /saas/status: current plan/status, billing-disabled flag and basic usage counts.

Email invitations and paid subscription billing are intentionally not enabled yet.

## Verification

Run a non-mutating smoke test with existing real accounts:

    JD_TEST_USER_A_EMAIL='owner-a@example.com' JD_TEST_USER_A_PASSWORD='...' node cloudflare/tests/saas-smoke.mjs

Set optional JD_TEST_USER_B_EMAIL and JD_TEST_USER_B_PASSWORD to test tenant isolation with two accounts that belong to different businesses. The script creates no business records; it only creates and revokes sign-in sessions. It verifies health, anonymous rejection, login, active business resolution, workspace listing, SaaS status, core read endpoints, denied cross-tenant switching, and record-ID overlap across tenant collections.

## Remaining production gates

- Run the smoke test with two separate real business accounts.
- Test the full real-data workflow in the UI: customer -> invoice -> receipt -> PDF/JPG -> analytics.
- Add email delivery and invitation acceptance before claiming email invitations are supported.
- Add subscription billing only after selecting a provider and testing payment lifecycle/webhooks.
- Test backups and restore, session revocation, rate limits, and authorization for every newly added endpoint.
- Review financial postings, inventory edge cases, and reconciliation with a qualified accountant before positioning the product as accounting-compliance software.
