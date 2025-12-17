-- Add rotation column to file_metadata table
ALTER TABLE file_metadata
ADD COLUMN rotation INT NOT NULL DEFAULT 0;
