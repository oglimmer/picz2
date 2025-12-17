-- Create analytics_events table to track public gallery usage
CREATE TABLE analytics_events (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    event_type VARCHAR(50) NOT NULL,
    album_id BIGINT NOT NULL,
    filter_tag VARCHAR(255),
    recording_id BIGINT,
    user_agent VARCHAR(1000),
    ip_address VARCHAR(45),
    visitor_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_analytics_album FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE,
    CONSTRAINT fk_analytics_recording FOREIGN KEY (recording_id) REFERENCES slideshow_recordings(id) ON DELETE SET NULL
);

-- Add indexes for efficient querying
CREATE INDEX idx_analytics_album_id ON analytics_events(album_id);
CREATE INDEX idx_analytics_event_type ON analytics_events(event_type);
CREATE INDEX idx_analytics_created_at ON analytics_events(created_at);
CREATE INDEX idx_analytics_visitor_id ON analytics_events(visitor_id);
CREATE INDEX idx_analytics_album_created ON analytics_events(album_id, created_at);
