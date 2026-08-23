-- Scoped upload tokens: a credential that can only start an upload.
--
-- Background (§5.9). TUS uploads carry their authentication inside `Upload-Metadata` as
-- plaintext `email:password`, because tusd does not forward arbitrary headers to its hooks and
-- the metadata is the only channel that reaches the pre-create handler. base64 is not
-- encryption, and tusd persists the metadata of every in-progress upload to a `.info` object in
-- object storage — so the user's actual account password was being written to disk, on a path
-- with a different lifetime and a different backup story from the credential store.
--
-- A token fixes the blast radius rather than the channel: it still travels in the metadata, but
-- it authenticates nothing except starting an upload, it expires, and it can be thrown away
-- without touching the account. The account password stays where it belongs.
--
-- Only the SHA-256 of the token is stored. The table then holds nothing that can be replayed if
-- it leaks — the same reason a password column holds a hash.
CREATE TABLE upload_tokens (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    -- Hex SHA-256 of the token the client holds. Unique so a lookup is a single index probe.
    token_hash VARCHAR(64) NOT NULL,
    user_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    -- Checked on every use. Rows past this are dead weight and are swept on the next issue.
    expires_at TIMESTAMP NOT NULL,
    CONSTRAINT uk_upload_tokens_hash UNIQUE (token_hash),
    CONSTRAINT fk_upload_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Serves the expiry sweep.
CREATE INDEX idx_upload_tokens_expires ON upload_tokens (expires_at);
