/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import lombok.Data;

@Data
@Entity
@Table(name = "users")
public class User {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(nullable = false, unique = true)
  private String email;

  @Column(nullable = false)
  private String password;

  @Column(name = "created_at", nullable = false, updatable = false)
  private LocalDateTime createdAt;

  @OneToMany(mappedBy = "user", cascade = CascadeType.ALL, orphanRemoval = true)
  private List<Album> albums = new ArrayList<>();

  @OneToMany(mappedBy = "user", cascade = CascadeType.ALL, orphanRemoval = true)
  private List<Tag> tags = new ArrayList<>();

  /**
   * How many bytes this user may keep on the instance's own storage. Only the system backend is
   * metered — an album on their own S3 costs us nothing and is neither counted nor capped.
   *
   * <p>100 MiB by default, changed with an {@code UPDATE} on this column; there is deliberately no
   * API for it, because raising your own allowance is not a thing a user should be able to do.
   */
  @Column(name = "storage_quota_bytes", nullable = false)
  private Long storageQuotaBytes = 104857600L;

  @Column(name = "default_album_id")
  private Long defaultAlbumId;

  @Column(name = "email_verified", nullable = false)
  private boolean emailVerified = false;

  @Column(name = "verification_token", length = 64)
  private String verificationToken;

  @Column(name = "verification_token_expiry")
  private Instant verificationTokenExpiry;

  @Column(name = "password_reset_token", length = 64)
  private String passwordResetToken;

  @Column(name = "password_reset_token_expiry")
  private Instant passwordResetTokenExpiry;

  @PrePersist
  protected void onCreate() {
    createdAt = LocalDateTime.now();
  }
}
