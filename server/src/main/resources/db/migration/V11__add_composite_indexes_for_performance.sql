-- Add composite index for album_id + display_order to optimize the most common query
-- This index is used when fetching files for an album sorted by display order
DROP INDEX IF EXISTS idx_display_order ON file_metadata;
CREATE INDEX idx_album_display_order ON file_metadata(album_id, display_order);

-- Add index on album share_token for share link queries
CREATE INDEX idx_album_share_token ON albums(share_token);
