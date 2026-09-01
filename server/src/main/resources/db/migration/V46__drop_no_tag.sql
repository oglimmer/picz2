-- D68: the `no_tag` marker is retired.
--
-- `no_tag` was an internal flag meaning "this asset carries no real tag". Every UI hid it and no
-- query ever selected on it, so it only ever cost bookkeeping. Its replacement is the `all` tag,
-- which the server now attaches to every newly registered asset (FileStorageService.addAllTagToFile).
--
-- Existing assets are deliberately NOT backfilled with `all`: assets uploaded before this migration
-- keep whatever real tags they have and otherwise end up with none. Tagging them is a manual,
-- per-album decision.
--
-- ON DELETE CASCADE on image_tags.tag_id would clear the junction rows on its own, but the explicit
-- DELETE keeps the intent readable and makes the row count visible in the migration log.

DELETE it FROM image_tags it
    JOIN tags t ON t.id = it.tag_id
WHERE t.name = 'no_tag';

DELETE FROM tags WHERE name = 'no_tag';
