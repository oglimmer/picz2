-- Add content_id column to file_metadata table
-- This field stores a unique identifier from the source (e.g., iOS PHAsset.localIdentifier)
-- to prevent duplicate uploads from the same source
ALTER TABLE file_metadata
ADD COLUMN content_id VARCHAR(255);

-- Add index for efficient duplicate detection
CREATE INDEX idx_content_id ON file_metadata(content_id);

-- Add composite index for user+contentId lookups (for multi-tenant duplicate detection)
CREATE INDEX idx_content_id_user ON file_metadata(content_id, album_id);
