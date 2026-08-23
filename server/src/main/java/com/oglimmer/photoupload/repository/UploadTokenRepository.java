/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.UploadToken;
import java.time.Instant;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface UploadTokenRepository extends JpaRepository<UploadToken, Long> {

  /** Joins the user eagerly: the caller always needs it, and the hook has no open session later. */
  @Query("SELECT t FROM UploadToken t JOIN FETCH t.user WHERE t.tokenHash = :tokenHash")
  Optional<UploadToken> findByTokenHash(@Param("tokenHash") String tokenHash);

  /**
   * Sweeps expired rows. Called opportunistically when a token is issued rather than on a schedule
   * — issuing is the only event that grows this table, so it is also the only moment that needs to
   * shrink it, and that keeps the whole mechanism inside one service.
   */
  @Modifying
  @Query("DELETE FROM UploadToken t WHERE t.expiresAt < :cutoff")
  int deleteExpired(@Param("cutoff") Instant cutoff);

  /** Used on password change / logout-everywhere to make outstanding tokens useless. */
  @Modifying
  @Query("DELETE FROM UploadToken t WHERE t.user.id = :userId")
  int deleteByUserId(@Param("userId") Long userId);
}
