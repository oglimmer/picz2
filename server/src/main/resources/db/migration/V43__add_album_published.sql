-- Explicit publish gate for albums.
--
-- Before this, an album was public the moment it was created: the share token is generated in
-- createAlbum, so the link worked while the album was still empty, and the subscription
-- notifier would mail people about a half-filled album. `published` makes that a decision the
-- owner takes, not a side effect of pressing "New album".
--
-- Unpublished means the whole share-token surface answers 404 (album, files, presentation
-- groups, recordings, analytics, subscribe) and the notifier skips the album entirely. It does
-- not revoke image tokens already handed out — /api/i/{token} stays open, the same as it is for
-- any album, because the owner's own gallery serves its thumbnails through it.
--
-- published_at is when the album first went public. The "new albums from this owner" notifier
-- keys off it instead of created_at: an album created on Monday and published on Friday is new
-- to a subscriber on Friday.
ALTER TABLE albums
    ADD COLUMN published BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN published_at TIMESTAMP NULL;

-- Every album that predates this column was already reachable by its share link. Turning them
-- off here would break live links, so they stay published; only albums created from now on
-- start unpublished.
UPDATE albums SET published = TRUE, published_at = created_at;
