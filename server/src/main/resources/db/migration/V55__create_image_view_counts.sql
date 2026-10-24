-- How often visitors on the public share page looked at each photo up close (D90).
--
-- One row per album, photo and visitor, not one row per look: the counters are added to in place
-- (INSERT ... ON DUPLICATE KEY UPDATE), so the table grows with photos x visitors and not with
-- every arrow-key press. Keeping the visitor in the key is what lets the owner see "seen by 4
-- people" next to "opened 11 times".
--
-- opens    = the visitor clicked the photo (in the grid or on the map) to open it full screen.
-- walk_ins = the visitor reached it with next/previous while already full screen.
CREATE TABLE image_view_counts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    album_id BIGINT NOT NULL,
    file_metadata_id BIGINT NOT NULL,
    visitor_id VARCHAR(255) NOT NULL,
    opens INT NOT NULL DEFAULT 0,
    walk_ins INT NOT NULL DEFAULT 0,
    first_seen_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_seen_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_image_view_album FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE,
    CONSTRAINT fk_image_view_file FOREIGN KEY (file_metadata_id) REFERENCES file_metadata(id) ON DELETE CASCADE,
    UNIQUE KEY uk_image_view (album_id, file_metadata_id, visitor_id),
    INDEX idx_image_view_file (file_metadata_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
