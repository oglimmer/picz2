/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.User;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface AlbumRepository extends JpaRepository<Album, Long> {

  // User-scoped queries
  Optional<Album> findByUserAndName(User user, String name);

  Optional<Album> findByUserAndId(User user, Long id);

  /**
   * The album's storage backend, without loading the album. {@code open-in-view} is off, so a lazy
   * {@code album.getStorageBackend()} outside a transaction would throw; the storage layer needs
   * the backend on every serve and every upload, so it asks for it directly.
   */
  @Query("SELECT a.storageBackend FROM Album a WHERE a.id = :albumId")
  Optional<StorageBackend> findStorageBackendByAlbumId(@Param("albumId") Long albumId);

  List<Album> findByUserOrderByDisplayOrderAsc(User user);

  @Query("SELECT COALESCE(MAX(a.displayOrder), -1) FROM Album a WHERE a.user = :user")
  Integer findMaxDisplayOrderByUser(User user);

  // Public access via share token (no user scoping needed)
  Optional<Album> findByShareToken(String shareToken);

  /**
   * The share-token lookup every public entry point must use. An unpublished album is invisible
   * rather than forbidden — an empty Optional here becomes the same 404 as a token that was never
   * issued, so the link leaks nothing about whether the album exists.
   *
   * <p>Use {@link #findByShareToken} only where the owner is already authenticated, or where the
   * caller must reach an unpublished album on purpose (unsubscribing, for instance).
   */
  Optional<Album> findByShareTokenAndPublishedTrue(String shareToken);

  /**
   * Albums of this owner that went public after a point in time — the feed behind the "new albums"
   * subscription. Keyed on publishedAt, not createdAt: a subscriber should hear about an album when
   * it becomes visible to them, and never about one that is still a draft.
   */
  List<Album> findByUserAndPublishedTrueAndPublishedAtAfter(User user, Instant publishedAt);

  /**
   * Bulk-delete the album row, bypassing JPA cascade so we don't pull the entire {@code files}
   * collection into the persistence context. Caller must already have removed dependent
   * file_metadata rows (FK is ON DELETE RESTRICT). Other album-scoped tables cascade in SQL.
   */
  @Modifying(clearAutomatically = true)
  @Query("DELETE FROM Album a WHERE a.id = :id")
  int bulkDeleteById(@Param("id") Long id);
}
