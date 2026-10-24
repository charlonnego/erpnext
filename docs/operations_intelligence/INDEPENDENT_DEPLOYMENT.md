# Joe&dave Operations Intelligence — independent deployment

## Product requirement

Joe&dave is a standalone, independently hosted web application built on the Frappe/ERPNext framework. A customer must not need to own, connect, or install anything into an existing ERPNext site. Each Joe&dave environment runs its own Frappe site and its own database; the deployment operator manages the application, database, queue, workers, scheduler, backups, and upgrades.

The current repository is a modified ERPNext codebase with the Operations Intelligence feature branch. It is not yet a packaged, running production service. Keep this distinction explicit in product copy and release notes.

## Correct runtime architecture

- **Web application and API:** Frappe/ERPNext app served by a supported Linux/Docker origin.
- **Database:** MariaDB, which is the database used by Frappe/ERPNext. Do not attach PostgreSQL to the Frappe site as its primary database.
- **Queue and cache:** Redis-compatible services required by the selected Frappe Docker release.
- **Background execution:** Frappe workers, scheduler, and websocket/socket.io service.
- **Persistent storage:** durable database storage plus protected private/public file storage and regular backups.
- **Public edge and preview:** Cloudflare DNS, TLS, proxy/WAF and optionally Access for a private preview. Cloudflare Pages can host the product landing page and a static, honest preview; it cannot run the complete Python Frappe server, MariaDB, Redis, and workers by itself.
- **Independent customer data:** use a dedicated Frappe site/database per customer for the first single-customer deployment. For a future multi-company SaaS, explicitly design and test tenant isolation before sharing an application site between customer businesses.

## Deployment path

1. Build and pin a compatible Frappe/ERPNext Docker image that includes the Joe&dave changes. Do not run a moving latest image in production.
2. Start the full supported Frappe Docker stack (backend, frontend/nginx, websocket, workers, scheduler, Redis cache/queue, and MariaDB) using the matching upstream Frappe Docker deployment configuration. Keep credentials in the hosting platform's secret manager, never in Git.
3. Create a new Frappe site owned by Joe&dave, initialize its own MariaDB database, and install the modified ERPNext app/code into that site. This is Joe&dave's own site—not a dependency on a customer's site.
4. Apply migrations and assets, create the initial administrator securely, and configure company defaults, accounts, fiscal year, currency, warehouses and user roles. Do not seed sample financial transactions into production.
5. Put the application behind Cloudflare DNS/TLS/proxy once the origin is reachable. Cloudflare Pages may continue to host the landing/preview; route the actual app hostname to the running origin. Do not expose database or Redis ports publicly.
6. Validate authentication, permissions, company boundaries, invoices, payment entries, stock reconciliation, imports, background jobs, file access, backups and restore before onboarding a real business.
7. Record the exact image tag, Frappe/ERPNext versions, commit SHA, migrations, backup timestamp and rollback plan for every release.

## Cloudflare limitation

A Pages deployment is not the ERPNext server. A static Pages site has no persistent Python process, Frappe scheduler, MariaDB, or Redis. Cloudflare Workers are not a drop-in runtime for the complete Frappe stack. Use Cloudflare as the public edge and preview host while the full app runs on a compatible container/VM host, or choose a compatible host that supports the entire Docker stack. The production UI can still be opened from a Cloudflare-managed hostname.

## Validation and release gates

- Run the official, version-matched Frappe/ERPNext tests and Joe&dave tests in a disposable test site.
- Confirm all supported DocType fields, whitelisted method permissions, company filters, list/report permissions and stock workflow behavior against the pinned version.
- Test inventory CSV validation, opening stock valuation, stock reconciliation drafts, serial/batch restrictions and failed-import recovery.
- Test financial figures against known test records created only in a disposable test database; never use fabricated numbers in the customer-facing live view.
- Verify background worker/scheduler health, persistent disk behavior, database backup and a successful restore.
- Perform security review, dependency/license review, GPLv3 source/notice compliance, trademark review and a rollback rehearsal.
- Mark the product production-ready only after these gates pass.

## Licensing and attribution

Joe&dave can create and commercially offer a modified product using open-source components, subject to each component's license and trademark rules. This repository is an ERPNext fork. Preserve upstream copyright and license notices, document our changes, include the applicable license, and meet the source-availability obligations for covered GPLv3 distributions. Do not imply official Frappe/ERPNext endorsement or claim exclusive ownership of upstream code. This is an engineering guide, not legal advice.

## Current status

- Operations Intelligence features and business workflow code exist on custom/operations-intelligence.
- The Cloudflare Pages address is a static preview only.
- No independent Frappe site, MariaDB database, Redis services, workers or production origin has been verified as running from this repository yet.
- The Render tools require an explicitly selected workspace before creating or modifying services. Do not provision resources until the correct workspace is confirmed and costs/plan constraints are understood.
