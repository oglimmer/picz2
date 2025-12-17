-- Add share token to albums for presentation links
ALTER TABLE albums
  ADD COLUMN IF NOT EXISTS share_token VARCHAR(128) UNIQUE NULL;
