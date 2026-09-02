-- D69: a per-asset caption, written by the album owner and read by everybody.
--
-- One free-text field per asset, shown under the photo in the gallery overview and inside the
-- lightbox/zoom view. It is deliberately NOT a comment thread: only the owner writes it, so there
-- is no author column, no timestamp and nothing for a public visitor to post to.
--
-- Nullable with no default: NULL and '' both mean "no caption", and the API normalises a blank
-- write to NULL so only one of them ever reaches the database.

ALTER TABLE file_metadata ADD COLUMN caption TEXT NULL;
