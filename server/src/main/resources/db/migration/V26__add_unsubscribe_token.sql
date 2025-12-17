ALTER TABLE album_subscriptions
ADD COLUMN unsubscribe_token VARCHAR(64) UNIQUE;

CREATE INDEX idx_album_subscriptions_unsubscribe_token ON album_subscriptions(unsubscribe_token);
