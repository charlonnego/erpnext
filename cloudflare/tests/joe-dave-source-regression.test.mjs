import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');

test('membership migration permits HR without weakening existing roles', () => {
  const migration = read('../d1/migrations/0006_hr_membership_role.sql');
  assert.match(migration, /'owner','admin','accountant','sales','inventory','viewer','hr'/);
  assert.match(migration, /INSERT INTO jd_business_memberships_new[\s\S]*SELECT id,business_id,user_id,role,invited_by,created_at FROM jd_business_memberships/);
  assert.match(migration, /jd_membership_keep_owner_before_delete/);
  assert.match(migration, /jd_membership_keep_owner_before_update/);
});

test('HR claims are shared only with HR and accounting roles in the API role gate', () => {
  const worker = read('../worker.js');
  assert.match(worker, /if\(group==="hr"\)return sub==="claims"\?\["hr","accountant"\]\.includes\(role\):role==="hr";/);
});

test('operational UI defaults to live API rather than silently saving only on the device', () => {
  const ui = read('../../products/joe-dave-operations-intelligence/operations-modules.js');
  assert.match(ui, /function localMode\(\)\{return localStorage\.getItem\(LOCAL_MODE_KEY\)==='local'\}/);
  assert.match(ui, /LOCAL MODE · DEVICE ONLY/);
});

test('responsive shell exposes an accessible collapsible module menu and phone/tablet/large-display layouts', () => {
  const html = read('../../products/joe-dave-operations-intelligence/index.html');
  assert.match(html, /id="nav-toggle"/);
  assert.match(html, /aria-controls="navwrap"/);
  assert.match(html, /@media\(max-width:480px\)/);
  assert.match(html, /@media\(max-width:900px\)/);
  assert.match(html, /@media\(min-width:1600px\)/);
  assert.match(html, /@media\(min-width:2200px\)/);
});
