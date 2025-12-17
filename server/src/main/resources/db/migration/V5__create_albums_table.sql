-- Create albums table
CREATE TABLE albums (
    id BIGINT NOT NULL AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
    display_order INT NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uk_album_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Add album_id foreign key to file_metadata table (REQUIRED - every image must belong to an album)
ALTER TABLE file_metadata
ADD COLUMN album_id BIGINT NOT NULL AFTER display_order,
ADD CONSTRAINT fk_file_metadata_album
    FOREIGN KEY (album_id)
    REFERENCES albums(id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE;

-- Create index on album_id for better query performance
CREATE INDEX idx_file_metadata_album_id ON file_metadata(album_id);
