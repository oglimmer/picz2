-- Browser sessions: a revocable credential in place of the account password.
--
-- The web app used to keep the plaintext password in localStorage and send it as Basic auth on
-- every request. base64 is not encryption (the D44 reasoning for tusd applies to the browser
-- too): any script that could read localStorage held the account for good, and there was nothing
-- the server could revoke short of the user changing their password.
--
-- A session token is what the browser holds instead. It is minted from one Basic-authenticated
-- login, expires on its own, and is deleted on logout and on every password change, so "I changed
-- my password" once more means "whatever had my old credentials is locked out". iOS keeps using
-- Basic; nothing there changes.
--
-- Same shape as upload_tokens, for the same reason: only the SHA-256 is stored, so a dump of
-- this table replays nothing.
CREATE TABLE session_tokens (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL,
    user_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    -- Checked on every request. Rows past this are swept on the next login.
    expires_at TIMESTAMP NOT NULL,
    CONSTRAINT uk_session_tokens_hash UNIQUE (token_hash),
    CONSTRAINT fk_session_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX idx_session_tokens_expires ON session_tokens (expires_at);
