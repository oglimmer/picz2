/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * A browser session (D78): what the web app holds instead of the account password.
 *
 * <p>The SPA used to keep the plaintext password in {@code localStorage} and send it as Basic auth
 * on every call. That made every XSS a permanent account takeover with nothing to revoke. A session
 * token is minted from one Basic-authenticated login, is sent as {@code Authorization: Bearer}, and
 * dies on logout, on expiry and on every password change.
 *
 * <p>Same shape as {@link UploadToken}: only {@code tokenHash} is stored, so a leaked dump of this
 * table replays nothing.
 */
@Entity
@Table(name = "session_tokens")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SessionToken {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  /** Hex SHA-256 of the token handed to the browser. The plaintext is never persisted. */
  @Column(name = "token_hash", nullable = false, unique = true, length = 64)
  private String tokenHash;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "user_id", nullable = false)
  private User user;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "expires_at", nullable = false)
  private Instant expiresAt;
}
