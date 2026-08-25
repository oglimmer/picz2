-- TRANSCODE_AUDIO_AAC queues work for a slideshow recording, not for an asset. The queue table is
-- reused rather than duplicated, so it needs a second, mutually exclusive subject column:
-- asset_id has a foreign key into file_metadata and a recording id can never satisfy it.
--
-- asset_id becomes nullable for exactly that reason. Every job type except TRANSCODE_AUDIO_AAC
-- still sets it, and NULL never satisfies a foreign key check, so the existing constraint keeps
-- doing its job for the rows that carry an asset.
ALTER TABLE processing_jobs
  MODIFY COLUMN asset_id BIGINT NULL;

ALTER TABLE processing_jobs
  ADD COLUMN recording_id BIGINT NULL AFTER asset_id;

-- ON DELETE CASCADE so deleting a recording also clears any transcode still queued for it —
-- otherwise the worker would lease a job whose subject is gone, fail it three times and
-- dead-letter it for no reason.
ALTER TABLE processing_jobs
  ADD CONSTRAINT fk_processing_jobs_recording
    FOREIGN KEY (recording_id) REFERENCES slideshow_recordings (id) ON DELETE CASCADE;
