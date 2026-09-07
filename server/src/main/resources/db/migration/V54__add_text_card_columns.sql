-- D86: a text card — an album entry that carries a chapter heading instead of a picture.
--
-- Stored as a file_metadata row, not in a table of its own. A card has to sit *between* photos in
-- the album's hand-made order, so it needs `display_order`, `album_id`, tags, delete and the share
-- listing — every one of which already exists on this row. A second table would have meant merging
-- and re-sorting two lists in the gallery, the public share page, the lightbox, iOS and the
-- subscription mail, and forgetting one of them.
--
-- What makes a card a card is its mime type: `application/x-picz-text-card`. That is deliberate,
-- not incidental. Every sweep, cover picker and rewrite gate in this schema already narrows on
-- `mime_type LIKE 'image/%'` or `'video/%'`, so a card is skipped by all of them with no new
-- condition anywhere: no thumbnail sweep, no transcode, no EXIF or GPS extraction, no album cover,
-- no rotate, no enhance. Retention skips it too, because a card has no `file_path`.
--
-- Hence no `kind` column: the wire's `kind` field is derived from the mime type in the mapper, so
-- there is one stored truth and it cannot drift from a second one.
--
-- `headline` is required for a card and null for a photo; `body_text` is optional for both but
-- only ever written on a card. Separate from `caption` on purpose — a caption belongs to a
-- picture, and mixing the two would put a card's paragraph into the photo caption editor.
ALTER TABLE file_metadata
    ADD COLUMN headline VARCHAR(200) NULL,
    ADD COLUMN body_text TEXT NULL;
