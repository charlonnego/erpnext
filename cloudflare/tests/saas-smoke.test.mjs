import test from "node:test";
import assert from "node:assert/strict";

const API = (process.env.JD_API_BASE_URL || "https://joe-dave-operations-api.uchechukwuanuforo.workers.dev").replace(/\/$/, "");
const firstEmail = process.env.JD_TEST_EMAIL;
const firstPassword = process.env.JD_TEST_PASSWORD;
const secondEmail = process.env.JD_SECOND_TEST_EMAIL;
const secondPassword = process.env.JD_SECOND_TEST_PASSWORD;

async function request(path, { token, method = "GET", body } = {}) {
  const headers = { Accept: "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const response = await fetch(API + path, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let data;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { response, data };
}

async function login(email, password) {
  const { response, data } = await request("/auth/login", {
    method: "POST", body: { email, password }
  });
  assert.equal(response.status, 200, "test account should be able to sign in");
  assert.equal(typeof data.token, "string");
  assert.ok(data.business?.id);
  return data;
}

test("production API health and database connectivity", async () => {
  const { response, data } = await request("/health");
  assert.equal(response.status, 200);
  assert.equal(data.ok, true);
  assert.equal(data.database, "connected");
  assert.ok(data.schema_tables > 0);
});

test("private workspace endpoints reject unauthenticated requests", async () => {
  for (const path of ["/auth/me", "/workspace/list", "/saas/status", "/business", "/analytics"]) {
    const { response } = await request(path);
    assert.equal(response.status, 401, `${path} must require authentication`);
  }
});

test("authenticated workspace read-only smoke checks", { skip: !(firstEmail && firstPassword) }, async () => {
  const auth = await login(firstEmail, firstPassword);
  const checks = [
    ["/auth/me", d => assert.equal(d.business.id, auth.business.id)],
    ["/workspace/list", d => assert.ok(Array.isArray(d.workspaces))],
    ["/saas/status", d => { assert.ok(d.plan); assert.equal(d.billing_enabled, false); }],
    ["/business", d => assert.equal(d.id, auth.business.id)],
    ["/analytics", d => assert.ok(d && typeof d === "object")],
    ["/customers", d => assert.ok(d && typeof d === "object")],
    ["/invoices", d => assert.ok(d && typeof d === "object")],
    ["/receipts", d => assert.ok(d && typeof d === "object")],
    ["/inventory", d => assert.ok(d && typeof d === "object")]
  ];
  for (const [path, verify] of checks) {
    const { response, data } = await request(path, { token: auth.token });
    assert.equal(response.status, 200, `${path} should load for the signed-in tenant`);
    verify(data);
  }
});

test("tenant boundary rejects switching to a business without membership", {
  skip: !(firstEmail && firstPassword && secondEmail && secondPassword)
}, async () => {
  const first = await login(firstEmail, firstPassword);
  const second = await login(secondEmail, secondPassword);
  assert.notEqual(first.business.id, second.business.id, "use two different business owners for this test");
  const { response } = await request("/workspace/switch", {
    token: first.token, method: "POST", body: { business_id: second.business.id }
  });
  assert.equal(response.status, 403, "a tenant must not switch into another tenant without membership");
});

test("cross-tenant invoice identifiers are not disclosed", {
  skip: !(firstEmail && firstPassword && secondEmail && secondPassword)
}, async () => {
  const first = await login(firstEmail, firstPassword);
  const second = await login(secondEmail, secondPassword);
  assert.notEqual(first.business.id, second.business.id, "use two different business owners for this test");
  const { response: listResponse, data: listData } = await request("/invoices", { token: second.token });
  assert.equal(listResponse.status, 200);
  const invoices = Array.isArray(listData) ? listData : (listData.invoices || listData.results || []);
  if (!invoices.length) return;
  const foreignId = invoices[0].id;
  assert.ok(foreignId);
  const { response } = await request("/invoices/" + encodeURIComponent(foreignId), { token: first.token });
  assert.equal(response.status, 404, "foreign tenant invoice should be indistinguishable from a missing invoice");
});
