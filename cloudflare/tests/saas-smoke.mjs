#!/usr/bin/env node
// Read-only SaaS smoke test. It creates no customers, invoices, receipts, or sample records.
// Login/logout only create and revoke temporary sessions.
import assert from 'node:assert/strict';

const BASE = (process.env.JD_API_BASE || 'https://joe-dave-operations-api.uchechukwuanuforo.workers.dev').replace(/\/$/, '');
const users = [
  { label: 'A', email: process.env.JD_TEST_USER_A_EMAIL, password: process.env.JD_TEST_USER_A_PASSWORD },
  { label: 'B', email: process.env.JD_TEST_USER_B_EMAIL, password: process.env.JD_TEST_USER_B_PASSWORD },
].filter(u => u.email && u.password);
if (!users.length) {
  console.error('Set JD_TEST_USER_A_EMAIL and JD_TEST_USER_A_PASSWORD for a real test account. Set optional B credentials to test tenant isolation.');
  process.exit(2);
}

const sessions = [];
const results = [];
async function request(path, options = {}) {
  const method = options.method || 'GET';
  const headers = { Accept: 'application/json' };
  if (options.token) headers.Authorization = 'Bearer ' + options.token;
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(BASE + path, { method, headers, body: options.body === undefined ? undefined : JSON.stringify(options.body) });
  const text = await response.text();
  let data;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text.slice(0, 200) }; }
  const expected = options.expected === undefined ? 200 : options.expected;
  assert.equal(response.status, expected, method + ' ' + path + ': expected HTTP ' + expected + ', got ' + response.status + '; ' + JSON.stringify(data));
  return data;
}
async function check(name, fn) {
  try { await fn(); results.push({ name, ok: true }); }
  catch (error) { results.push({ name, ok: false, error: error.message }); throw error; }
}
async function login(user) {
  const d = await request('/auth/login', { method: 'POST', body: { email: user.email, password: user.password } });
  assert.ok(d.token, 'login must return a session token');
  sessions.push(d.token);
  return Object.assign({}, user, { token: d.token });
}
const collectionPaths = ['/customers','/invoices','/receipts','/inventory','/expenses','/suppliers','/purchase-orders','/supplier-bills','/bank-accounts','/bank-transactions','/accounting-periods'];
function idsOf(value, out = new Set()) {
  if (Array.isArray(value)) for (const item of value) idsOf(item, out);
  else if (value && typeof value === 'object') {
    if (typeof value.id === 'string') out.add(value.id);
    for (const [key, child] of Object.entries(value)) if (key !== 'id') idsOf(child, out);
  }
  return out;
}
try {
  await check('API health and database connection', async () => {
    const h = await request('/health');
    assert.equal(h.ok, true);
    assert.equal(h.database, 'connected');
    assert.ok(Number(h.schema_tables) >= 20, 'core schema tables should be present');
  });
  await check('Protected endpoint rejects anonymous access', async () => {
    await request('/business', { expected: 401 });
  });

  const authenticated = [];
  for (const user of users) {
    await check('Account ' + user.label + ' login and tenant context', async () => {
      const u = await login(user);
      const me = await request('/auth/me', { token: u.token });
      const business = await request('/business', { token: u.token });
      assert.ok(me.user && me.user.id, 'auth/me must identify the signed-in user');
      assert.ok(me.business && me.business.id, 'auth/me must resolve a workspace');
      assert.equal(business.id, me.business.id, 'business endpoint must match active workspace');
      const list = await request('/workspace/list', { token: u.token });
      assert.ok(list.workspaces.some(w => w.id === business.id), 'active workspace must be in authorized workspace list');
      const saas = await request('/saas/status', { token: u.token });
      assert.equal(saas.billing_enabled, false, 'billing must not be represented as enabled');
      assert.ok(saas.plan && saas.subscription_status);
      for (const path of ['/dashboard','/analytics'].concat(collectionPaths, ['/journal','/reports/trial-balance','/reports/profit-loss','/reports/audit','/reports/inventory-valuation'])) {
        await request(path, { token: u.token });
      }
      await request('/workspace/members', { token: u.token });
      await request('/customers', { method: 'POST', token: u.token, body: {}, expected: 400 });
      await request('/invoices', { method: 'POST', token: u.token, body: {}, expected: 400 });
      await request('/inventory', { method: 'POST', token: u.token, body: {}, expected: 400 });
      await request('/workspace/switch', { method: 'POST', token: u.token, body: {}, expected: 400 });
      const collections = {};
      for (const path of collectionPaths) collections[path] = idsOf(await request(path, { token: u.token }));
      authenticated.push(Object.assign({}, u, { business, collections }));
    });
  }

  if (authenticated.length === 2) {
    await check('Two accounts resolve to different tenant workspaces', async () => {
      assert.notEqual(authenticated[0].business.id, authenticated[1].business.id, 'use two accounts belonging to different businesses for this test');
    });
    await check('Tenant A cannot switch into Tenant B', async () => {
      await request('/workspace/switch', { method: 'POST', token: authenticated[0].token, body: { business_id: authenticated[1].business.id }, expected: 403 });
    });
    await check('Collection endpoints do not return the same tenant record IDs', async () => {
      for (const path of collectionPaths) {
        const a = authenticated[0].collections[path], b = authenticated[1].collections[path];
        const overlap = Array.from(a).filter(id => b.has(id));
        assert.equal(overlap.length, 0, path + ' returned overlapping record IDs: ' + overlap.join(', '));
      }
    });
  } else {
    results.push({ name: 'Cross-tenant isolation', ok: false, skipped: true, error: 'Requires two existing accounts in separate businesses; only one account was configured.' });
  }
} finally {
  for (const token of sessions) {
    try { await request('/auth/logout', { method: 'POST', token }); }
    catch (error) { console.error('Logout warning:', error.message); }
  }
  console.log(JSON.stringify({ base: BASE, results }, null, 2));
}
if (results.some(r => !r.ok && !r.skipped)) process.exitCode = 1;
if (results.some(r => r.skipped)) process.exitCode = 2;
