-- Joe&dave Operations Intelligence — SaaS tenancy foundation (0005)
-- Existing owner data is preserved; no sample business or transaction data is inserted.
ALTER TABLE jd_sessions ADD COLUMN business_id TEXT REFERENCES jd_businesses(id);

CREATE TABLE IF NOT EXISTS jd_business_memberships (
 id TEXT PRIMARY KEY,
 business_id TEXT NOT NULL REFERENCES jd_businesses(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES jd_users(id) ON DELETE CASCADE,
 role TEXT NOT NULL CHECK(role IN ('owner','admin','accountant','sales','inventory','viewer')),
 invited_by TEXT REFERENCES jd_users(id),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 UNIQUE(business_id,user_id)
);
CREATE INDEX IF NOT EXISTS jd_memberships_user_idx ON jd_business_memberships(user_id,business_id);
CREATE INDEX IF NOT EXISTS jd_memberships_business_role_idx ON jd_business_memberships(business_id,role);

CREATE TABLE IF NOT EXISTS jd_business_subscriptions (
 business_id TEXT PRIMARY KEY REFERENCES jd_businesses(id) ON DELETE CASCADE,
 plan_code TEXT NOT NULL DEFAULT 'pilot' CHECK(plan_code IN ('pilot','starter','business','professional')),
 status TEXT NOT NULL DEFAULT 'pilot' CHECK(status IN ('pilot','active','past_due','cancelled')),
 provider TEXT,
 provider_customer_id TEXT,
 provider_subscription_id TEXT,
 current_period_start TEXT,
 current_period_end TEXT,
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

INSERT OR IGNORE INTO jd_business_memberships(id,business_id,user_id,role)
 SELECT lower(hex(randomblob(16))),id,owner_id,'owner' FROM jd_businesses;
INSERT OR IGNORE INTO jd_business_subscriptions(business_id,plan_code,status)
 SELECT id,'pilot','pilot' FROM jd_businesses;
UPDATE jd_sessions
 SET business_id=(
  SELECT m.business_id FROM jd_business_memberships m
  WHERE m.user_id=jd_sessions.user_id
  ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,m.created_at
  LIMIT 1
 )
 WHERE business_id IS NULL;

CREATE TRIGGER IF NOT EXISTS jd_membership_keep_owner_before_delete
BEFORE DELETE ON jd_business_memberships
WHEN OLD.role='owner' AND (SELECT COUNT(*) FROM jd_business_memberships WHERE business_id=OLD.business_id AND role='owner')<=1
BEGIN SELECT RAISE(ABORT,'A business must retain at least one owner'); END;

CREATE TRIGGER IF NOT EXISTS jd_membership_keep_owner_before_update
BEFORE UPDATE OF role ON jd_business_memberships
WHEN OLD.role='owner' AND NEW.role<>'owner'
 AND (SELECT COUNT(*) FROM jd_business_memberships WHERE business_id=OLD.business_id AND role='owner')<=1
BEGIN SELECT RAISE(ABORT,'A business must retain at least one owner'); END;
