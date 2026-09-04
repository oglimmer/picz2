-- Lets a presentation group stop before the next group starts.
--
-- Until now a group owned every image from its anchor up to the next anchor, so the last group of
-- a tag always ran to the end of the album and there was no way to say "this section is over".
-- end_file_id names the LAST image that still belongs to the group; NULL keeps the original
-- behaviour (run on until the next anchor), which is what every pre-existing row gets.
--
-- ON DELETE SET NULL, not CASCADE: losing the image a group ends at must not delete the group —
-- it just falls back to running until the next anchor.
ALTER TABLE presentation_groups
    ADD COLUMN end_file_id BIGINT NULL AFTER start_file_id,
    ADD CONSTRAINT fk_pg_end_file FOREIGN KEY (end_file_id) REFERENCES file_metadata(id) ON DELETE SET NULL;
