/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.User;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

@Repository
public interface AlbumRepository extends JpaRepository<Album, Long> {

  // User-scoped queries
  Optional<Album> findByUserAndName(User user, String name);

  Optional<Album> findByUserAndId(User user, Long id);

  List<Album> findByUserOrderByDisplayOrderAsc(User user);

  @Query("SELECT COALESCE(MAX(a.displayOrder), -1) FROM Album a WHERE a.user = :user")
  Integer findMaxDisplayOrderByUser(User user);

  // Public access via share token (no user scoping needed)
  Optional<Album> findByShareToken(String shareToken);

  // Find albums created by user after a specific time (for subscription notifications)
  List<Album> findByUserAndCreatedAtAfter(User user, Instant createdAt);
}
