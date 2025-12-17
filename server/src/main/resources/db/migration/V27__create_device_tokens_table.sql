CREATE TABLE device_tokens (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    device_token VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    platform VARCHAR(20) NOT NULL DEFAULT 'ios',
    app_version VARCHAR(50),
    device_model VARCHAR(100),
    os_version VARCHAR(50),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_active_at TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    failure_count INT NOT NULL DEFAULT 0,
    last_failure_reason VARCHAR(500),
    INDEX idx_email (email),
    INDEX idx_active (is_active),
    INDEX idx_device_token (device_token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
