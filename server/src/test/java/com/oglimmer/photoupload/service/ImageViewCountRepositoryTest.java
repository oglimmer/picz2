/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.repository.ImageViewCountRepository;
import com.oglimmer.photoupload.repository.ImageViewCountRepository.ImageViewRow;
import com.oglimmer.photoupload.repository.ImageViewCountRepository.ImageViewTotals;
import com.oglimmer.photoupload.testsupport.TestObjectStorage;
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
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.MinIOContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mariadb.MariaDBContainer;

/**
 * The per-photo counters' native SQL against a real MariaDB (D90): the upsert adds instead of
 * overwriting, the viewable filter drops hidden photos and text cards, and the owner's ranking
 * reads busiest first with one viewer per visitor.
 *
 * <p>Set up like {@link RetentionPurgeCandidatesTest}.
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
class ImageViewCountRepositoryTest {

  @Container @ServiceConnection
  static final MariaDBContainer MARIADB = new MariaDBContainer("mariadb:11.8").withReuse(false);

  @Container static final MinIOContainer MINIO = TestObjectStorage.newMinio();

  @DynamicPropertySource
  static void objectStorage(DynamicPropertyRegistry registry) {
    TestObjectStorage.register(registry, MINIO);
  }

  @Autowired private ImageViewCountRepository repository;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private TransactionTemplate tx;

  private Long userId;
  private Long albumId;

  @BeforeEach
  void seedFixtures() {
    jdbcTemplate.update(
        "INSERT INTO users (email, password) VALUES (?, ?)", "views@example.com", "irrelevant");
    userId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM users WHERE email = ?", Long.class, "views@example.com");
    jdbcTemplate.update("INSERT INTO albums (user_id, name) VALUES (?, 'Trip')", userId);
    albumId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM albums WHERE user_id = ? AND name = 'Trip'", Long.class, userId);
  }

  @AfterEach
  void cleanup() {
    jdbcTemplate.update("DELETE FROM image_view_counts");
    jdbcTemplate.update("DELETE FROM image_tags");
    jdbcTemplate.update("DELETE FROM file_metadata");
    jdbcTemplate.update("DELETE FROM tags WHERE user_id = ?", userId);
    jdbcTemplate.update("DELETE FROM albums WHERE user_id = ?", userId);
    jdbcTemplate.update("DELETE FROM users WHERE id = ?", userId);
  }

  @Test
  void theUpsertAddsToTheVisitorsRow() {
    Long photo = insertFile("image/jpeg");

    add(photo, "v-1", 1, 2);
    add(photo, "v-1", 1, 3);

    assertThat(
            jdbcTemplate.queryForList(
                "SELECT opens, walk_ins FROM image_view_counts WHERE file_metadata_id = ?", photo))
        .singleElement()
        .satisfies(
            row -> {
              assertThat(((Number) row.get("opens")).intValue()).isEqualTo(2);
              assertThat(((Number) row.get("walk_ins")).intValue()).isEqualTo(5);
            });
  }

  @Test
  void onlyPicturesAndVideosThatAreNotHiddenAreViewable() {
    Long photo = insertFile("image/jpeg");
    Long video = insertFile("video/mp4");
    Long card = insertFile("application/x-picz-text-card");
    Long hidden = insertFile("image/jpeg");
    tagHidden(hidden);

    List<Long> viewable =
        repository.findViewableIds(
            albumId, List.of(photo, video, card, hidden, 999_999L), SystemTags.HIDDEN);

    assertThat(viewable).containsExactlyInAnyOrder(photo, video);
    assertThat(repository.countViewable(albumId, SystemTags.HIDDEN)).isEqualTo(2);
  }

  @Test
  void theRankingIsBusiestFirstWithOneViewerPerVisitor() {
    Long quiet = insertFile("image/jpeg");
    Long busy = insertFile("image/jpeg");
    add(quiet, "v-1", 1, 0);
    add(busy, "v-1", 2, 4);
    add(busy, "v-2", 1, 1);

    List<ImageViewRow> top = repository.findTopImages(albumId, 50);

    assertThat(top).extracting(ImageViewRow::getFileId).containsExactly(busy, quiet);
    assertThat(top.get(0).getOpens()).isEqualTo(3);
    assertThat(top.get(0).getWalkIns()).isEqualTo(5);
    assertThat(top.get(0).getViewers()).isEqualTo(2);
    assertThat(repository.findTopImages(albumId, 1)).hasSize(1);

    ImageViewTotals totals = repository.findTotals(albumId);
    assertThat(totals.getImagesViewed()).isEqualTo(2);
    assertThat(totals.getOpens()).isEqualTo(4);
    assertThat(totals.getWalkIns()).isEqualTo(5);
  }

  @Test
  void anAlbumNobodyLookedAtHasZeroTotals() {
    ImageViewTotals totals = repository.findTotals(albumId);

    assertThat(totals.getImagesViewed()).isZero();
    assertThat(totals.getOpens()).isZero();
    assertThat(repository.findTopImages(albumId, 50)).isEmpty();
  }

  @Test
  void resetDeletesTheAlbumsRows() {
    Long photo = insertFile("image/jpeg");
    add(photo, "v-1", 1, 0);

    tx.executeWithoutResult(s -> repository.deleteByAlbumId(albumId));

    assertThat(repository.findTotals(albumId).getImagesViewed()).isZero();
  }

  private void add(Long fileId, String visitor, int opens, int walkIns) {
    tx.executeWithoutResult(
        s -> repository.addViews(albumId, fileId, visitor, opens, walkIns, Instant.now()));
  }

  private void tagHidden(Long fileId) {
    jdbcTemplate.update(
        "INSERT INTO tags (user_id, name) VALUES (?, ?)", userId, SystemTags.HIDDEN);
    Long tagId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM tags WHERE user_id = ? AND name = ?",
            Long.class,
            userId,
            SystemTags.HIDDEN);
    jdbcTemplate.update(
        "INSERT INTO image_tags (file_metadata_id, tag_id) VALUES (?, ?)", fileId, tagId);
  }

  private Long insertFile(String mimeType) {
    String suffix = String.valueOf(System.nanoTime());
    jdbcTemplate.update(
        "INSERT INTO file_metadata "
            + "(original_name, stored_filename, file_size, mime_type, uploaded_at, rotation, "
            + "display_order, album_id, processing_status, processing_attempts) "
            + "VALUES (?, ?, 1024, ?, NOW(6), 0, 0, ?, 'DONE', 0)",
        "it-" + suffix,
        "stored-" + suffix,
        mimeType,
        albumId);
    return jdbcTemplate.queryForObject(
        "SELECT id FROM file_metadata WHERE stored_filename = ?", Long.class, "stored-" + suffix);
  }
}
