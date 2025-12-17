-- Add EXIF DateTimeOriginal column to file_metadata table
ALTER TABLE file_metadata
    ADD COLUMN exif_date_time_original TIMESTAMP(6) NULL,
    ADD INDEX idx_exif_date_time_original (exif_date_time_original);
