-- Capture-time UTC offset, in seconds, as it applied at the moment of capture.
--
-- exif_date_time_original is a true instant, which is what album sort order needs but not what
-- "group by day" needs: the day a photo belongs to is the day the camera saw, not the day the
-- viewer's browser is in. A Toronto evening lands on the next morning in Frankfurt without this.
--
-- Nullable: rows written before this column existed carry no offset until the EXTRACT_CAPTURE_DATE
-- sweep re-reads them, and retention-purged originals can never be re-read at all.
ALTER TABLE file_metadata
  ADD COLUMN capture_utc_offset_seconds INT NULL;
