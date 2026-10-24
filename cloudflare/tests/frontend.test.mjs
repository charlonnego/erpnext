import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { spawnSync } from "node:child_process";

const path = "docs/operations_intelligence/demo/index.html";
const html = fs.readFileSync(path, "utf8");

test("all inline browser scripts parse as JavaScript modules", () => {
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map(m => m[1]).filter(s => s.trim());
  assert.ok(scripts.length >= 2, "expected the main app and API integration scripts");
  for (const [index, script] of scripts.entries()) {
    const result = spawnSync(process.execPath, ["--input-type=module", "--check"], { input: script, encoding: "utf8" });
    assert.equal(result.status, 0, "inline script " + (index + 1) + " failed syntax check: " + result.stderr);
  }
});

test("every navigation target has a matching section", () => {
  const nav = [...html.matchAll(/data-page="([^"]+)"/g)].map(m => m[1]);
  const pages = new Set([...html.matchAll(/id="page-([^"]+)"/g)].map(m => m[1]));
  for (const page of nav) assert.ok(pages.has(page), "missing section for nav target: " + page);
});

test("live business modules are wired to the API", () => {
  for (const route of ["/auth/register", "/customers", "/invoices", "/inventory/import", "/suppliers", "/expenses", "/purchase-orders", "/supplier-bills", "/bank-transactions/import", "/accounting-periods", "/reports/trial-balance", "/analytics", "/business", "/receipts"]) {
    assert.ok(html.includes(route), "missing UI API integration for " + route);
  }
});

test("branding, professional document export and data analysis controls exist", () => {
  for (const fragment of ["brand-logo-file", "invoice_template", "receipt_template", "invoice-pdf", "invoice-jpg", "receipt-pdf", "receipt-jpg", "analytics-chart", "analytics-insights", "api('/analytics')"]) {
    assert.ok(html.includes(fragment), "missing document/analytics feature: " + fragment);
  }
});
