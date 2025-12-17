-- V17: Add multi-tenancy support - Add user_id to albums, tags, and update constraints
--
-- This migration adds user_id foreign keys to albums and tags tables to enable
-- multi-tenancy where each user has their own isolated data space.
--
-- IMPORTANT: This migration assumes you have at least one user in the users table.
-- If the users table is empty, you must create a user first before running this migration.

-- Step 1: Add user_id column to albums table (nullable first, we'll make it NOT NULL after data migration)
ALTER TABLE albums
    ADD COLUMN user_id BIGINT NULL AFTER id,
    ADD CONSTRAINT fk_albums_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Step 2: Migrate existing albums to first user (or create a default user if none exists)
-- This assigns all existing albums to the first user in the database
UPDATE albums
SET user_id = (SELECT id FROM users ORDER BY id LIMIT 1)
WHERE user_id IS NULL;

-- Step 3: Make user_id NOT NULL now that all albums have a user
ALTER TABLE albums
    MODIFY COLUMN user_id BIGINT NOT NULL;

-- Step 4: Drop the old global unique constraint on album name
ALTER TABLE albums
    DROP INDEX uk_album_name;

-- Step 5: Add new composite unique constraint (user_id + name)
ALTER TABLE albums
    ADD CONSTRAINT uk_user_album_name UNIQUE (user_id, name);

-- Step 6: Add user_id column to tags table (nullable first)
ALTER TABLE tags
    ADD COLUMN user_id BIGINT NULL AFTER id,
    ADD CONSTRAINT fk_tags_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Step 7: Migrate existing tags to first user
UPDATE tags
SET user_id = (SELECT id FROM users ORDER BY id LIMIT 1)
WHERE user_id IS NULL;

delete from tags;

-- Step 8: Make user_id NOT NULL for tags
ALTER TABLE tags
    MODIFY COLUMN user_id BIGINT NOT NULL;

-- Step 9: Drop the old global unique constraint on tag name
ALTER TABLE tags
    DROP INDEX name;

-- Step 10: Add new composite unique constraint for tags (user_id + name)
ALTER TABLE tags
    ADD CONSTRAINT uk_user_tag_name UNIQUE (user_id, name);

-- Step 11: Add index on user_id for albums (for performance)
CREATE INDEX idx_albums_user_id ON albums(user_id);

-- Step 12: Add index on user_id for tags (for performance)
CREATE INDEX idx_tags_user_id ON tags(user_id);

-- Note: slideshow_recordings table doesn't need user_id directly as it's linked to albums,
-- which are now user-scoped. User access is controlled through the album relationship.
