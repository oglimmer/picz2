-- Create file_metadata table
CREATE TABLE file_metadata (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    original_name VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL UNIQUE,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100),
    file_path VARCHAR(512) NOT NULL,
    uploaded_at TIMESTAMP(6) NOT NULL,
    checksum VARCHAR(64),
    width INT,
    height INT,
    duration BIGINT,
    INDEX idx_stored_filename (stored_filename),
    INDEX idx_uploaded_at (uploaded_at),
    INDEX idx_mime_type (mime_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
