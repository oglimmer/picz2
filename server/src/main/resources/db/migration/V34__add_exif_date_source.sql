-- Records which tag exif_date_time_original was derived from.
--
-- Rows written before the timezone-aware extractor hold a photo's local wall clock relabelled
-- UTC (metadata-extractor's single-arg getDate() hardcodes GMT for zone-less EXIF strings and
-- ignores OffsetTimeOriginal), while videos always held a true UTC instant. That put the two
-- media types on different clocks and sheared them apart in EXIF sort order.
--
-- NULL = legacy value, never re-extracted. The EXTRACT_CAPTURE_DATE sweep selects on it, so the
-- eligible set shrinks as the sweep progresses and repeat runs converge.
ALTER TABLE file_metadata
    ADD COLUMN exif_date_source VARCHAR(32) NULL,
    ADD INDEX idx_exif_date_source (exif_date_source);
