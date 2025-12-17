-- Add public token to file metadata for unauthenticated image access via secret IDs
ALTER TABLE file_metadata
  ADD COLUMN IF NOT EXISTS public_token VARCHAR(64) UNIQUE NULL;

-- Backfill existing rows with random tokens
UPDATE file_metadata
SET public_token = LOWER(REPLACE(UUID(), '-', ''))
WHERE public_token IS NULL;
