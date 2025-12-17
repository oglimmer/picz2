-- Create tags table
CREATE TABLE tags (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create image_tags junction table for many-to-many relationship
CREATE TABLE image_tags (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    file_metadata_id BIGINT NOT NULL,
    tag_id BIGINT NOT NULL,
    tagged_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    FOREIGN KEY (file_metadata_id) REFERENCES file_metadata(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE,
    UNIQUE KEY uk_file_tag (file_metadata_id, tag_id),
    INDEX idx_file_metadata_id (file_metadata_id),
    INDEX idx_tag_id (tag_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert some predefined tags
INSERT INTO tags (name) VALUES
    ('family'),
    ('vacation'),
    ('work'),
    ('nature'),
    ('friends'),
    ('events'),
    ('food'),
    ('pets');
