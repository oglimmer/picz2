-- Where a photo or video was taken, lifted out of the original's EXIF GPS IFD (images) or the
-- com.apple.quicktime.location.ISO6709 tag (videos), so the gallery can plot assets on a map.
--
-- Stored as signed decimal degrees, WGS 84 — the same reference frame EXIF and ISO 6709 use and
-- the one MapKit JS expects, so no datum conversion happens anywhere in the pipeline.
--
-- gps_source mirrors exif_date_source: NULL means "never looked", a written value (including
-- NONE) means "looked, this is what the file had". The EXTRACT_GPS sweep selects on NULL, so the
-- eligible set shrinks with every pass and repeat runs converge.
--
-- Coordinates live only in the original. Retention-purged rows (file_path IS NULL) can never be
-- backfilled, so the sweep excludes them rather than enqueueing jobs that are certain to fail.
ALTER TABLE file_metadata
    ADD COLUMN gps_latitude DOUBLE NULL,
    ADD COLUMN gps_longitude DOUBLE NULL,
    ADD COLUMN gps_source VARCHAR(32) NULL,
    ADD INDEX idx_gps_source (gps_source),
    ADD INDEX idx_album_gps (album_id, gps_latitude);
