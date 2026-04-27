-- Track explicit processing state for each uploaded asset.
-- Backfill: rows that already have any derivative (thumbnail, medium, large, transcoded)
-- are considered DONE; the rest are FAILED so they can be re-queued by hand without
-- being mistaken for finished work.
ALTER TABLE file_metadata
  ADD COLUMN processing_status VARCHAR(32) NOT NULL DEFAULT 'INGESTED',
  ADD COLUMN processing_attempts INT NOT NULL DEFAULT 0,
  ADD COLUMN processing_error TEXT NULL,
  ADD COLUMN processing_completed_at DATETIME(6) NULL;

UPDATE file_metadata
SET processing_status = 'DONE',
    processing_completed_at = uploaded_at
WHERE thumbnail_path IS NOT NULL
   OR medium_path IS NOT NULL
   OR large_path IS NOT NULL
   OR transcoded_video_path IS NOT NULL;

UPDATE file_metadata
SET processing_status = 'FAILED'
WHERE processing_status = 'INGESTED';

CREATE INDEX idx_file_metadata_processing_status ON file_metadata(processing_status);
