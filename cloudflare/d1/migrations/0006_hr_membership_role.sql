-- Joe&dave membership role compatibility: HR is a first-class restricted role.
-- Rebuild the table to extend the SQLite CHECK constraint without dropping existing memberships.
CREATE TABLE jd_business_memberships_new (
 id TEXT PRIMARY KEY,
 business_id TEXT NOT NULL REFERENCES jd_businesses(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES jd_users(id) ON DELETE CASCADE,
 role TEXT NOT NULL CHECK(role IN ('owner','admin','accountant','sales','inventory','viewer','hr')),
 invited_by TEXT REFERENCES jd_users(id),
 created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 UNIQUE(business_id,user_id)
);
INSERT INTO jd_business_memberships_new(id,business_id,user_id,role,invited_by,created_at)
 SELECT id,business_id,user_id,role,invited_by,created_at FROM jd_business_memberships;
DROP TABLE jd_business_memberships;
ALTER TABLE jd_business_memberships_new RENAME TO jd_business_memberships;
CREATE INDEX IF NOT EXISTS jd_memberships_user_idx ON jd_business_memberships(user_id,business_id);
CREATE INDEX IF NOT EXISTS jd_memberships_business_role_idx ON jd_business_memberships(business_id,role);
CREATE TRIGGER IF NOT EXISTS jd_membership_keep_owner_before_delete
BEFORE DELETE ON jd_business_memberships
WHEN OLD.role='owner' AND (SELECT COUNT(*) FROM jd_business_memberships WHERE business_id=OLD.business_id AND role='owner')<=1
BEGIN SELECT RAISE(ABORT,'A business must retain at least one owner'); END;
CREATE TRIGGER IF NOT EXISTS jd_membership_keep_owner_before_update
BEFORE UPDATE OF role ON jd_business_memberships
WHEN OLD.role='owner' AND NEW.role<>'owner'
 AND (SELECT COUNT(*) FROM jd_business_memberships WHERE business_id=OLD.business_id AND role='owner')<=1
BEGIN SELECT RAISE(ABORT,'A business must retain at least one owner'); END;
