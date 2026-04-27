-- Persistent jobs table that replaces the in-memory ThreadPoolTaskExecutor queue.
-- Workers lease rows with SELECT ... FOR UPDATE SKIP LOCKED so a crashed worker's
-- jobs become re-leaseable once leased_until passes.
CREATE TABLE processing_jobs (
  id              BIGINT       NOT NULL AUTO_INCREMENT,
  asset_id        BIGINT       NOT NULL,
  status          VARCHAR(32)  NOT NULL,
  attempts        INT          NOT NULL DEFAULT 0,
  max_attempts    INT          NOT NULL DEFAULT 3,
  leased_until    DATETIME(6)  NULL,
  leased_by       VARCHAR(128) NULL,
  last_error      TEXT         NULL,
  created_at      DATETIME(6)  NOT NULL,
  started_at      DATETIME(6)  NULL,
  finished_at     DATETIME(6)  NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_processing_jobs_asset
    FOREIGN KEY (asset_id) REFERENCES file_metadata (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- The dispatcher's hot path is "next leaseable row": status='QUEUED' OR
-- (status='PROCESSING' AND leased_until < NOW()). The composite index covers both.
CREATE INDEX idx_processing_jobs_status_lease
  ON processing_jobs (status, leased_until);

-- Backfill: V30 marked every row missing all derivatives as FAILED. Re-enqueue them
-- so the new dispatcher picks them up. Reset their FileMetadata status to QUEUED so
-- the gauge and admin views agree with the jobs table.
INSERT INTO processing_jobs (asset_id, status, attempts, max_attempts, created_at)
SELECT id, 'QUEUED', 0, 3, NOW(6)
FROM file_metadata
WHERE processing_status = 'FAILED';

UPDATE file_metadata
SET processing_status = 'QUEUED',
    processing_attempts = 0,
    processing_error = NULL,
    processing_completed_at = NULL
WHERE processing_status = 'FAILED';
