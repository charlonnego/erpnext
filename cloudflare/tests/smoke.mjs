import test from "node:test";
import assert from "node:assert/strict";

const base = (process.env.API_URL || "https://joe-dave-operations-api.uchechukwuanuforo.workers.dev").replace(/\/$/, "");

test("public health confirms API and D1 schema", async () => {
  const response = await fetch(base + "/health");
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.database, "connected");
  assert.ok(body.schema_tables >= 15);
});

test("private dashboard rejects unauthenticated access", async () => {
  const response = await fetch(base + "/dashboard");
  assert.equal(response.status, 401);
  const body = await response.json();
  assert.match(body.error, /sign in/i);
});

test("CORS rejects an untrusted origin", async () => {
  const response = await fetch(base + "/health", {
    headers: { Origin: "https://attacker.invalid" }
  });
  assert.equal(response.status, 403);
});

test("invalid invoice receipt cannot be posted anonymously", async () => {
  const response = await fetch(base + "/invoices/not-a-real-id/receipts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ amount_minor: 100, payment_method: "cash" })
  });
  assert.equal(response.status, 401);
});
