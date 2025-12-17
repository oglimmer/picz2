CREATE TABLE album_subscriptions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    album_id BIGINT NOT NULL,
    notify_album_updates BOOLEAN NOT NULL DEFAULT TRUE,
    notify_new_albums BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_notified_at TIMESTAMP NULL,
    confirmation_token VARCHAR(64) UNIQUE,
    confirmed BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT fk_album_subscription_album FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE,
    CONSTRAINT uk_album_subscription_email_album UNIQUE (email, album_id)
);

CREATE INDEX idx_album_subscriptions_email ON album_subscriptions(email);
CREATE INDEX idx_album_subscriptions_album_id ON album_subscriptions(album_id);
CREATE INDEX idx_album_subscriptions_confirmation_token ON album_subscriptions(confirmation_token);
CREATE INDEX idx_album_subscriptions_active_confirmed ON album_subscriptions(active, confirmed);
