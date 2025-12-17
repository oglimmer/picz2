-- Add email verification fields to users table
ALTER TABLE users
ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN verification_token VARCHAR(64),
ADD COLUMN verification_token_expiry TIMESTAMP;

-- Add index for verification token lookups
CREATE INDEX idx_verification_token ON users(verification_token);

-- Verify existing users (backwards compatibility)
UPDATE users SET email_verified = TRUE WHERE email_verified = FALSE;
