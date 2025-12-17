/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface TagRepository extends JpaRepository<Tag, Long> {

  // User-scoped queries
  Optional<Tag> findByUserAndName(User user, String name);

  Optional<Tag> findByUserAndId(User user, Long id);

  boolean existsByUserAndName(User user, String name);

  List<Tag> findByUser(User user);
}
