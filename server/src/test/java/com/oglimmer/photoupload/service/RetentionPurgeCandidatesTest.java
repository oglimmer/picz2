/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.testsupport.TestObjectStorage;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MinIOContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mariadb.MariaDBContainer;

/**
 * The scope of the nightly original-purge, against a real MariaDB (D89). Retention deletes bytes
 * for good, and the scope lives in a native query no unit test can see: an aged original on the
 * system default backend is a candidate, the same original in an album on a user's own storage
 * never is.
 *
 * <p>Set up like {@link ProcessingJobLeaseTest}: worker profile, MOCK web environment, MariaDB and
 * MinIO containers, gated on {@code -Drun.testcontainers=true}.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.MOCK,
    properties = {
      "app.apns.enabled=false",
      "app.mail.enabled=false",
      "spring.mail.host=localhost",
      "jobs.poll.interval-ms=86400000"
    })
@ActiveProfiles("worker")
@Testcontainers
@EnabledIfSystemProperty(
    named = "run.testcontainers",
    matches = "true",
    disabledReason =
        "Requires Docker access for Testcontainers. Run with `mvn test -Drun.testcontainers=true`")
class RetentionPurgeCandidatesTest {

  @Container @ServiceConnection
  static final MariaDBContainer MARIADB = new MariaDBContainer("mariadb:11.8").withReuse(false);

  @Container static final MinIOContainer MINIO = TestObjectStorage.newMinio();

  @DynamicPropertySource
  static void objectStorage(DynamicPropertyRegistry registry) {
    TestObjectStorage.register(registry, MINIO);
  }

  @Autowired private FileMetadataRepository metadataRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  private Long userId;
  private Long systemAlbumId;
  private Long ownStorageAlbumId;

  @BeforeEach
  void seedFixtures() {
    jdbcTemplate.update(
        "INSERT INTO users (email, password) VALUES (?, ?)", "retention@example.com", "irrelevant");
    userId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM users WHERE email = ?", Long.class, "retention@example.com");

    // The user's home server. Never contacted: the query only reads rows.
    jdbcTemplate.update(
        "INSERT INTO storage_backends (user_id, name, endpoint, bucket, access_key) "
            + "VALUES (?, 'Home server', 'https://abc123def456.myfritz.net', 'picz', 'picz')",
        userId);
    Long ownBackendId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM storage_backends WHERE user_id = ?", Long.class, userId);

    // storage_backend_id defaults to 1, the system default.
    jdbcTemplate.update("INSERT INTO albums (user_id, name) VALUES (?, 'On the site')", userId);
    systemAlbumId = albumId("On the site");
    jdbcTemplate.update(
        "INSERT INTO albums (user_id, name, storage_backend_id) VALUES (?, 'At home', ?)",
        userId,
        ownBackendId);
    ownStorageAlbumId = albumId("At home");
  }

  @AfterEach
  void cleanup() {
    jdbcTemplate.update("DELETE FROM file_metadata");
    jdbcTemplate.update("DELETE FROM albums WHERE user_id = ?", userId);
    jdbcTemplate.update("DELETE FROM storage_backends WHERE user_id = ?", userId);
    jdbcTemplate.update("DELETE FROM users WHERE id = ?", userId);
  }

  @Test
  void onlyOriginalsOnTheSystemDefaultAreCandidates() {
    Long onTheSite = insertAgedOriginal(systemAlbumId);
    Long atHome = insertAgedOriginal(ownStorageAlbumId);

    List<FileMetadata> candidates =
        metadataRepository.findRetentionPurgeCandidates(
            Instant.now().minus(Duration.ofDays(7)), 100);

    assertThat(candidates).extracting(FileMetadata::getId).containsExactly(onTheSite);
    assertThat(candidates).extracting(FileMetadata::getId).doesNotContain(atHome);
  }

  private Long albumId(String name) {
    return jdbcTemplate.queryForObject(
        "SELECT id FROM albums WHERE user_id = ? AND name = ?", Long.class, userId, name);
  }

  /** A finished photo, uploaded a month ago, whose original is still stored. */
  private Long insertAgedOriginal(Long albumId) {
    String suffix = String.valueOf(System.nanoTime());
    jdbcTemplate.update(
        "INSERT INTO file_metadata "
            + "(original_name, stored_filename, file_size, mime_type, file_path, thumbnail_path, "
            + "uploaded_at, rotation, display_order, album_id, processing_status, "
            + "processing_attempts) "
            + "VALUES (?, ?, ?, ?, ?, ?, DATE_SUB(NOW(6), INTERVAL 30 DAY), 0, 0, ?, 'DONE', 0)",
        "it-" + suffix + ".jpg",
        "stored-" + suffix + ".jpg",
        1024L,
        "image/jpeg",
        "originals/" + suffix + ".jpg",
        "derivatives/" + suffix + "/thumb.jpg",
        albumId);
    return jdbcTemplate.queryForObject(
        "SELECT id FROM file_metadata WHERE stored_filename = ?",
        Long.class,
        "stored-" + suffix + ".jpg");
  }
}
