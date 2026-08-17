-- Presentation image groups: a per-(album, tag) section marker anchored to the image the
-- group starts at. Rendering walks the tag-filtered file list in display_order; every image
-- from an anchor up to the next anchor belongs to that group.
--
-- start_file_id cascades: deleting the anchor image drops the group, which is the correct
-- behaviour — the section it introduced no longer has a start.
CREATE TABLE presentation_groups (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    album_id BIGINT NOT NULL,
    tag_id BIGINT NOT NULL,
    start_file_id BIGINT NOT NULL,
    label VARCHAR(120) NOT NULL,
    -- Matches PresentationGroupService.MAX_TEXT_LENGTH; VARCHAR keeps ddl-auto:validate happy
    -- (a TEXT column reports as LONGVARCHAR, which Hibernate will not accept for a String field).
    body_text VARCHAR(4000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT NULL,
    CONSTRAINT fk_pg_album FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE,
    CONSTRAINT fk_pg_tag FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE,
    CONSTRAINT fk_pg_start_file FOREIGN KEY (start_file_id) REFERENCES file_metadata(id) ON DELETE CASCADE,
    CONSTRAINT uk_pg_album_tag_start UNIQUE (album_id, tag_id, start_file_id),
    INDEX idx_pg_album_tag (album_id, tag_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
