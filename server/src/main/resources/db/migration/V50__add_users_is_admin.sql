-- D74: an explicit operator flag.
--
-- `/api/admin/*` used to require nothing but a login. Every account had the same (empty) set of
-- authorities, so any registered user could run the S3 orphan purge with dryRun=false, trigger the
-- backfill sweeps, or read the dead-letter list with other users' asset ids and errors.
--
-- Same shape as `storage_quota_bytes`: no UI, no API, set with SQL —
--   UPDATE users SET is_admin = TRUE WHERE email = 'you@example.com';
-- Nobody is promoted here. A fresh deploy has no admin until the operator names one.
ALTER TABLE users
  ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT FALSE;
