-- Remove gallery_title setting as title is now hardcoded to 'Picz'
DELETE FROM gallery_settings WHERE setting_key = 'gallery_title';
