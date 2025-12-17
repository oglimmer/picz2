-- Add thumbnail path columns to file_metadata table for performance optimization
ALTER TABLE file_metadata
  ADD COLUMN IF NOT EXISTS thumbnail_path VARCHAR(512) NULL,
  ADD COLUMN IF NOT EXISTS medium_path VARCHAR(512) NULL,
  ADD COLUMN IF NOT EXISTS large_path VARCHAR(512) NULL;

-- Add index on public_token for faster lookups (explicit index, though UNIQUE creates one)
CREATE INDEX IF NOT EXISTS idx_public_token ON file_metadata(public_token);
