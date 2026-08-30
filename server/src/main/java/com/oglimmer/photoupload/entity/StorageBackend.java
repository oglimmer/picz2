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
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * An S3-compatible endpoint an album's bytes can live in. Two shapes share this table:
 *
 * <ul>
 *   <li><b>system default</b> — {@code systemDefault=true}, {@code user=null}. A handle for the
 *       operator's MinIO. Its endpoint, bucket and credentials stay null here on purpose and are
 *       resolved from {@code storage.s3.*} at runtime, so rotating the cluster secret does not need
 *       a database write and the secret is never duplicated into a row.
 *   <li><b>user backend</b> — owned by one {@link User}, who pays for the storage. Endpoint, bucket
 *       and access key are readable; the secret key is stored encrypted (see {@code SecretCipher})
 *       and never leaves the server.
 * </ul>
 *
 * <p>An album points at exactly one of these and cannot be moved afterwards, so a row referenced by
 * an album cannot be deleted (FK is {@code ON DELETE RESTRICT}).
 */
@Entity
@Table(
    name = "storage_backends",
    uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "name"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class StorageBackend {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  /** Owner, or null for the system default which every user may select. */
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "user_id")
  private User user;

  @Column(name = "name", nullable = false)
  private String name;

  @Column(name = "system_default", nullable = false)
  private boolean systemDefault = false;

  /** Full URL including scheme, e.g. {@code https://s3.eu-central-1.amazonaws.com}. */
  @Column(name = "endpoint", length = 512)
  private String endpoint;

  @Column(name = "region", nullable = false, length = 64)
  private String region = "us-east-1";

  @Column(name = "bucket")
  private String bucket;

  @Column(name = "access_key")
  private String accessKey;

  /** AES-GCM ciphertext produced by {@code SecretCipher}; never rendered to a client. */
  @Column(name = "secret_key_encrypted", length = 1024)
  private String secretKeyEncrypted;

  /**
   * MinIO and most self-hosted gateways need path-style addressing ({@code endpoint/bucket/key}).
   * AWS S3 proper accepts either. Defaults to true because the self-hosted case is the reason this
   * feature exists.
   */
  @Column(name = "path_style_access", nullable = false)
  private boolean pathStyleAccess = true;

  @Column(name = "created_at", nullable = false)
  private Instant createdAt;

  @Column(name = "updated_at")
  private Instant updatedAt;

  @PrePersist
  protected void onCreate() {
    if (createdAt == null) {
      createdAt = Instant.now();
    }
    updatedAt = Instant.now();
  }

  @PreUpdate
  protected void onUpdate() {
    updatedAt = Instant.now();
  }
}
