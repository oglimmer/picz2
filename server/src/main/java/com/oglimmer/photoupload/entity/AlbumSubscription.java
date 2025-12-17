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
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(
    name = "album_subscriptions",
    uniqueConstraints = @UniqueConstraint(columnNames = {"email", "album_id"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class AlbumSubscription {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "email", nullable = false)
  private String email;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "album_id", nullable = false)
  private Album album;

  @Column(name = "notify_album_updates", nullable = false)
  private Boolean notifyAlbumUpdates = true;

  @Column(name = "notify_new_albums", nullable = false)
  private Boolean notifyNewAlbums = false;

  @Column(name = "created_at", nullable = false)
  private Instant createdAt;

  @Column(name = "last_notified_at")
  private Instant lastNotifiedAt;

  @Column(name = "confirmation_token", unique = true, length = 64)
  private String confirmationToken;

  @Column(name = "unsubscribe_token", unique = true, length = 64)
  private String unsubscribeToken;

  @Column(name = "confirmed", nullable = false)
  private Boolean confirmed = false;

  @Column(name = "active", nullable = false)
  private Boolean active = true;

  @PrePersist
  protected void onCreate() {
    if (createdAt == null) {
      createdAt = Instant.now();
    }
    if (confirmationToken == null) {
      confirmationToken = UUID.randomUUID().toString().replace("-", "");
    }
    if (unsubscribeToken == null) {
      unsubscribeToken = UUID.randomUUID().toString().replace("-", "");
    }
  }
}
