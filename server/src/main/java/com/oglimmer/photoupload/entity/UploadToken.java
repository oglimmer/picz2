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
 * A credential that can start an upload and do nothing else (§5.9, D44).
 *
 * <p>TUS uploads authenticate through {@code Upload-Metadata}, because tusd forwards no arbitrary
 * headers to its hooks. That metadata is base64, not encryption, and tusd writes it to a {@code
 * .info} object in storage for the life of the upload — so putting the account password there put
 * it on disk with a different lifetime and a different backup story from the credential store.
 *
 * <p>This does not fix the channel; it fixes what travels through it. A token authorises exactly
 * one thing, expires on its own, and can be discarded without touching the account.
 *
 * <p>Only {@code tokenHash} is stored. A leaked dump of this table replays nothing.
 */
@Entity
@Table(name = "upload_tokens")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UploadToken {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  /** Hex SHA-256 of the token handed to the client. The plaintext is never persisted. */
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
