-- Create slideshow_recordings table
CREATE TABLE slideshow_recordings (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    album_id BIGINT NOT NULL,
    filter_tag VARCHAR(255),
    audio_filename VARCHAR(512) NOT NULL,
    audio_path VARCHAR(1024) NOT NULL,
    duration_ms BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_recording_album FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
);

-- Create slideshow_recording_images table
CREATE TABLE slideshow_recording_images (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    recording_id BIGINT NOT NULL,
    file_id BIGINT NOT NULL,
    start_time_ms BIGINT NOT NULL,
    duration_ms BIGINT NOT NULL,
    sequence_order INT NOT NULL,
    CONSTRAINT fk_recording_image_recording FOREIGN KEY (recording_id) REFERENCES slideshow_recordings(id) ON DELETE CASCADE,
    CONSTRAINT fk_recording_image_file FOREIGN KEY (file_id) REFERENCES file_metadata(id) ON DELETE CASCADE
);

-- Add indexes for performance
CREATE INDEX idx_recording_album ON slideshow_recordings(album_id);
CREATE INDEX idx_recording_created ON slideshow_recordings(created_at);
CREATE INDEX idx_recording_image_recording ON slideshow_recording_images(recording_id);
CREATE INDEX idx_recording_image_file ON slideshow_recording_images(file_id);
CREATE INDEX idx_recording_image_sequence ON slideshow_recording_images(recording_id, sequence_order);
