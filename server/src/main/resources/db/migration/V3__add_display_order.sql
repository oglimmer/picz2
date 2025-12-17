-- Add display_order column to file_metadata table
ALTER TABLE file_metadata ADD COLUMN display_order INT NOT NULL DEFAULT 0;

-- Create index for sorting
CREATE INDEX idx_display_order ON file_metadata(display_order);

-- Set initial order based on upload time (older files first)
UPDATE file_metadata SET display_order = id;
