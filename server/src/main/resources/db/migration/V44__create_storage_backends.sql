-- Per-album object storage. Until now every byte landed in the one MinIO bucket named by
-- storage.s3.* — the operator's disk, the operator's bill. This table lets a user register
-- their own S3-compatible endpoint and point an album at it, so the metadata stays here and
-- the (expensive) storage is theirs.
--
-- Two kinds of row live here:
--   * the system backend (user_id IS NULL, system_default = TRUE) — a stand-in for the
--     configured storage.s3.* MinIO. Its endpoint/credentials are deliberately NOT stored;
--     they are resolved from application config at runtime so the cluster secret never gets
--     copied into the database.
--   * user backends (user_id set) — endpoint, bucket and access key in clear, secret key
--     encrypted with storage.backend-secret-key (AES-GCM, see SecretCipher).
--
-- An album's backend is fixed at creation. Changing it later would mean moving every object,
-- and a half-moved album has no correct answer for a presigned URL, so the API rejects the
-- change instead. The FK is ON DELETE RESTRICT for the same reason: a backend still holding
-- an album's bytes cannot be deleted out from under it.
CREATE TABLE storage_backends (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    name VARCHAR(255) NOT NULL,
    system_default BOOLEAN NOT NULL DEFAULT FALSE,
    endpoint VARCHAR(512) NULL,
    region VARCHAR(64) NOT NULL DEFAULT 'us-east-1',
    bucket VARCHAR(255) NULL,
    access_key VARCHAR(255) NULL,
    secret_key_encrypted VARCHAR(1024) NULL,
    path_style_access BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    -- Doubles as the lookup index for "this user's backends"; a leading-column prefix of a
    -- unique key is a usable index, so InnoDB needs no separate one for the FK either.
    UNIQUE KEY uk_storage_backend_user_name (user_id, name),
    CONSTRAINT fk_storage_backend_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- id 1 is referenced as the fallback by the albums default below, so it must exist first and
-- must keep that id. AUTO_INCREMENT starts at 1 on an empty table, but the id is written
-- explicitly rather than assumed.
INSERT INTO storage_backends (id, user_id, name, system_default) VALUES (1, NULL, 'Default storage', TRUE);

ALTER TABLE albums
    ADD COLUMN storage_backend_id BIGINT NOT NULL DEFAULT 1,
    ADD CONSTRAINT fk_album_storage_backend
        FOREIGN KEY (storage_backend_id) REFERENCES storage_backends(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE;
