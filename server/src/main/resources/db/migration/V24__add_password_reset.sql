-- Add password reset fields to users table
ALTER TABLE users
ADD COLUMN password_reset_token VARCHAR(64),
ADD COLUMN password_reset_token_expiry TIMESTAMP;

-- Add index for password reset token lookups
CREATE INDEX idx_password_reset_token ON users(password_reset_token);
