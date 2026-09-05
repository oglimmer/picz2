/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.SessionToken;
import java.time.Instant;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface SessionTokenRepository extends JpaRepository<SessionToken, Long> {

  /** Joins the user eagerly: the filter needs it on every request and has no open session later. */
  @Query("SELECT t FROM SessionToken t JOIN FETCH t.user WHERE t.tokenHash = :tokenHash")
  Optional<SessionToken> findByTokenHash(@Param("tokenHash") String tokenHash);

  /** Swept opportunistically on login — the only event that grows this table. */
  @Modifying
  @Query("DELETE FROM SessionToken t WHERE t.expiresAt < :cutoff")
  int deleteExpired(@Param("cutoff") Instant cutoff);

  /** Logout: one session. */
  @Modifying
  @Query("DELETE FROM SessionToken t WHERE t.tokenHash = :tokenHash")
  int deleteByTokenHash(@Param("tokenHash") String tokenHash);

  /** Password change / reset: every session of the account. */
  @Modifying
  @Query("DELETE FROM SessionToken t WHERE t.user.id = :userId")
  int deleteByUserId(@Param("userId") Long userId);
}
