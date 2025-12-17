-- Add public token to slideshow recordings for unauthenticated access via secret IDs
ALTER TABLE slideshow_recordings
  ADD COLUMN IF NOT EXISTS public_token VARCHAR(64) UNIQUE NULL;

-- Backfill existing rows with random tokens
UPDATE slideshow_recordings
SET public_token = LOWER(REPLACE(UUID(), '-', ''))
WHERE public_token IS NULL;
