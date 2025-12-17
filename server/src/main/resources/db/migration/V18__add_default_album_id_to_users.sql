-- Add default_album_id column to users table
ALTER TABLE users ADD COLUMN default_album_id BIGINT;

-- Add foreign key constraint (optional, ensures referential integrity)
-- Note: This allows NULL values, which is intentional for users who haven't set a default album yet
ALTER TABLE users ADD CONSTRAINT fk_users_default_album
    FOREIGN KEY (default_album_id) REFERENCES albums(id) ON DELETE SET NULL;
