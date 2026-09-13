/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.StorageBackend;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface StorageBackendRepository extends JpaRepository<StorageBackend, Long> {

  Optional<StorageBackend> findBySystemDefaultTrue();

  Optional<StorageBackend> findByIdAndUserId(Long id, Long userId);

  boolean existsByUserIdAndName(Long userId, String name);

  /**
   * The set a user may choose from when creating an album: their own backends plus the system
   * default. Ordered so the system default comes first — it is the pre-selected option in every
   * client.
   */
  @Query(
      "SELECT b FROM StorageBackend b WHERE b.systemDefault = true OR b.user.id = :userId"
          + " ORDER BY b.systemDefault DESC, b.name ASC")
  List<StorageBackend> findSelectableForUser(Long userId);

  /**
   * Guard for delete: an album still holding bytes there pins the backend. Every user's albums
   * count, which is right for the only backends that can be deleted — a user's own, which only that
   * user's albums can use. Never show this number to a user: on the system default it is the whole
   * instance's album count.
   */
  @Query("SELECT COUNT(a) FROM Album a WHERE a.storageBackend.id = :backendId")
  long countAlbumsUsing(Long backendId);

  /**
   * How many of one user's albums live on a backend — the number the storage list shows. On the
   * system default the unscoped {@link #countAlbumsUsing} would report every album on the instance.
   */
  @Query(
      "SELECT COUNT(a) FROM Album a WHERE a.storageBackend.id = :backendId AND a.user.id = :userId")
  long countAlbumsOfUserUsing(Long backendId, Long userId);
}
