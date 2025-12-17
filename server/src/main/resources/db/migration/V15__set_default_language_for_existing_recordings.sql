-- Set default language for all existing recordings to 'language1' (German)
UPDATE slideshow_recordings
SET language = 'language1'
WHERE language IS NULL;
