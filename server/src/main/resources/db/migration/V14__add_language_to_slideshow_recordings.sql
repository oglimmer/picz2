-- Add language column to slideshow_recordings table
ALTER TABLE slideshow_recordings
ADD COLUMN language VARCHAR(50);

-- Create index on language for faster filtering
CREATE INDEX idx_slideshow_recordings_language ON slideshow_recordings(language);
