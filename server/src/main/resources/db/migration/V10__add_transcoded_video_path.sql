-- Add transcoded video path column to file_metadata table for Safari/iOS video compatibility
ALTER TABLE file_metadata
  ADD COLUMN IF NOT EXISTS transcoded_video_path VARCHAR(512) NULL;
