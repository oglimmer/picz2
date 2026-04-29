-- Discriminator for the kind of work a processing_jobs row represents.
-- PROCESS      = upload pipeline (download original → derivatives) — the only kind before V32.
-- ROTATE_LEFT  = admin rotate (download → rotate-90-CCW → re-PUT original → regenerate derivatives).
-- Future admin operations (regenerate-thumbnails, video-date-backfill, …) extend this enum.
ALTER TABLE processing_jobs
  ADD COLUMN job_type VARCHAR(32) NOT NULL DEFAULT 'PROCESS' AFTER asset_id;
