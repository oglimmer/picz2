-- Per-user storage limit on the instance's own MinIO.
--
-- Only the system backend is metered. An album on the user's own S3 costs us nothing, so it is
-- not counted and not capped — the point of "bring your own storage" (V44) is that the user pays
-- for what they keep, and a cap on their own bucket would be us rationing their disk.
--
-- The TUS staging prefix is not counted either. Bytes under `tus-uploads/` are in flight, live
-- for minutes, and are swept by retention whether or not the upload finished; charging for them
-- would bill a user for transport rather than for storage.
--
-- 100 MiB by default. There is no UI for changing it: raise a specific user's allowance with
--   UPDATE users SET storage_quota_bytes = 5368709120 WHERE email = '…';   -- 5 GiB
-- and 0 means "no uploads at all", which is a usable way to freeze an abusive account.
ALTER TABLE users
    ADD COLUMN storage_quota_bytes BIGINT NOT NULL DEFAULT 104857600;

-- What the derivatives of one asset actually occupy: thumb + medium + large + transcoded, summed
-- as they are written. Needed because retention deletes originals after a week — without this the
-- metered usage of a month-old account would fall back to nearly zero while its thumbnails and
-- transcoded videos stay on the disk for good, and the quota would measure nothing.
--
-- Existing rows start at 0 and therefore under-count until the asset is reprocessed. Run
-- `POST /api/admin/recalculate-derivative-bytes` once after deploying to backfill them from the
-- bucket's own object sizes.
ALTER TABLE file_metadata
    ADD COLUMN derivative_bytes BIGINT NOT NULL DEFAULT 0;

-- Slideshow narration: the master plus its derived .m4a sibling, summed. Nullable because a row
-- written before this column existed genuinely does not know, and 0 would claim it was free.
ALTER TABLE slideshow_recordings
    ADD COLUMN audio_bytes BIGINT NULL;
