/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.MariaDBContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Album-wide tag add/remove against a real MariaDB. The mock-based {@code
 * FileStorageServiceBulkTagTest} can only assert which repository calls happen — it cannot see
 * Hibernate's flush, and the {@code no_tag} bookkeeping here depends on it: the bulk methods load
 * {@code FileMetadata.imageTags} via JOIN FETCH, and that collection is mapped {@code
 * CascadeType.ALL} + {@code orphanRemoval}, so a row deleted behind the collection's back gets
 * re-persisted on flush. Only a real transaction commit shows that.
 */
// Note: the default MOCK web environment, not NONE — the api profile's SecurityConfig needs the
// CorsConfigurationSource that WebMvc auto-config contributes.
@SpringBootTest(
    properties = {"app.apns.enabled=false", "app.mail.enabled=false", "spring.mail.host=localhost"})
@ActiveProfiles("api")
@Testcontainers
@EnabledIfSystemProperty(
    named = "run.testcontainers",
    matches = "true",
    disabledReason =
        "Requires Docker access for Testcontainers. Run with `mvn test -Drun.testcontainers=true`")
class FileStorageServiceBulkTagIT {

  private static final String EMAIL = "bulktag-it@example.com";

  @Container @ServiceConnection
  static final MariaDBContainer<?> MARIADB =
      new MariaDBContainer<>("mariadb:11.8").withReuse(false);

  @Autowired private FileStorageService fileStorageService;
  @Autowired private JdbcTemplate jdbcTemplate;

  private Long userId;
  private Long albumId;
  private Long onlyNoTag;
  private Long onlyRealTag;
  private Long noTagPlusRealTag;

  @BeforeEach
  void seedFixtures() {
    jdbcTemplate.update("INSERT INTO users (email, password) VALUES (?, ?)", EMAIL, "irrelevant");
    userId = jdbcTemplate.queryForObject("SELECT id FROM users WHERE email = ?", Long.class, EMAIL);

    jdbcTemplate.update(
        "INSERT INTO albums (user_id, name) VALUES (?, ?)", userId, "bulktag-album");
    albumId =
        jdbcTemplate.queryForObject(
            "SELECT id FROM albums WHERE user_id = ? AND name = ?",
            Long.class,
            userId,
            "bulktag-album");

    Long noTagId = insertTag(FileStorageService.NO_TAG);
    Long beachId = insertTag("beach");

    // Three starting states a real album can be in.
    onlyNoTag = insertFile("a");
    tagFile(onlyNoTag, noTagId);

    onlyRealTag = insertFile("b");
    tagFile(onlyRealTag, beachId);

    // Inconsistent leftover: no_tag sitting next to a real tag.
    noTagPlusRealTag = insertFile("c");
    tagFile(noTagPlusRealTag, noTagId);
    tagFile(noTagPlusRealTag, beachId);

    SecurityContextHolder.getContext()
        .setAuthentication(
            new UsernamePasswordAuthenticationToken(
                EMAIL, "irrelevant", AuthorityUtils.createAuthorityList("ROLE_USER")));
  }

  @AfterEach
  void cleanup() {
    SecurityContextHolder.clearContext();
    jdbcTemplate.update(
        "DELETE FROM image_tags WHERE file_metadata_id IN"
            + " (SELECT id FROM file_metadata WHERE album_id = ?)",
        albumId);
    jdbcTemplate.update("DELETE FROM file_metadata WHERE album_id = ?", albumId);
    jdbcTemplate.update("DELETE FROM albums WHERE user_id = ?", userId);
    jdbcTemplate.update("DELETE FROM tags WHERE user_id = ?", userId);
    jdbcTemplate.update("DELETE FROM users WHERE id = ?", userId);
  }

  @Test
  void addingAllToEveryFileClearsNoTagEverywhere() {
    int changed = fileStorageService.addTagToAllFilesInAlbum(albumId, FileStorageService.ALL_TAG);

    assertThat(changed).isEqualTo(3);
    assertThat(tagsOf(onlyNoTag)).containsExactly(FileStorageService.ALL_TAG);
    assertThat(tagsOf(onlyRealTag)).containsExactly(FileStorageService.ALL_TAG, "beach");
    assertThat(tagsOf(noTagPlusRealTag)).containsExactly(FileStorageService.ALL_TAG, "beach");
    // The invariant that matters: no_tag never coexists with a real tag.
    assertThat(noTagRowCount()).isZero();
  }

  @Test
  void addingAllTwiceIsANoOp() {
    fileStorageService.addTagToAllFilesInAlbum(albumId, FileStorageService.ALL_TAG);
    int changed = fileStorageService.addTagToAllFilesInAlbum(albumId, FileStorageService.ALL_TAG);

    assertThat(changed).isZero();
    assertThat(tagsOf(onlyNoTag)).containsExactly(FileStorageService.ALL_TAG);
    assertThat(noTagRowCount()).isZero();
  }

  @Test
  void removingAllRestoresNoTagOnlyWhereNothingElseRemains() {
    fileStorageService.addTagToAllFilesInAlbum(albumId, FileStorageService.ALL_TAG);

    int changed =
        fileStorageService.removeTagFromAllFilesInAlbum(albumId, FileStorageService.ALL_TAG);

    assertThat(changed).isEqualTo(3);
    // The tag really is gone — not resurrected by a cascade on flush.
    assertThat(tagsOf(onlyNoTag)).containsExactly(FileStorageService.NO_TAG);
    assertThat(tagsOf(onlyRealTag)).containsExactly("beach");
    assertThat(tagsOf(noTagPlusRealTag)).containsExactly("beach");
  }

  private List<String> tagsOf(Long fileId) {
    return jdbcTemplate.queryForList(
        "SELECT t.name FROM image_tags it JOIN tags t ON t.id = it.tag_id"
            + " WHERE it.file_metadata_id = ? ORDER BY t.name",
        String.class,
        fileId);
  }

  private int noTagRowCount() {
    return jdbcTemplate.queryForObject(
        "SELECT COUNT(*) FROM image_tags it JOIN tags t ON t.id = it.tag_id"
            + " JOIN file_metadata f ON f.id = it.file_metadata_id"
            + " WHERE f.album_id = ? AND t.name = ?",
        Integer.class,
        albumId,
        FileStorageService.NO_TAG);
  }

  private Long insertTag(String name) {
    jdbcTemplate.update("INSERT INTO tags (user_id, name) VALUES (?, ?)", userId, name);
    return jdbcTemplate.queryForObject(
        "SELECT id FROM tags WHERE user_id = ? AND name = ?", Long.class, userId, name);
  }

  private void tagFile(Long fileId, Long tagId) {
    jdbcTemplate.update(
        "INSERT INTO image_tags (file_metadata_id, tag_id) VALUES (?, ?)", fileId, tagId);
  }

  private Long insertFile(String suffix) {
    String stored = "bulktag-" + suffix + ".jpg";
    jdbcTemplate.update(
        "INSERT INTO file_metadata "
            + "(original_name, stored_filename, file_size, mime_type, file_path, uploaded_at, "
            + "rotation, display_order, album_id, processing_status, processing_attempts) "
            + "VALUES (?, ?, ?, ?, ?, NOW(6), 0, 0, ?, 'DONE', 0)",
        stored,
        stored,
        1024L,
        "image/jpeg",
        stored,
        albumId);
    return jdbcTemplate.queryForObject(
        "SELECT id FROM file_metadata WHERE stored_filename = ?", Long.class, stored);
  }
}
