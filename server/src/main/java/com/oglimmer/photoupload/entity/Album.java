/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "albums", uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "name"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Album {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "user_id", nullable = false)
  private User user;

  @Column(name = "name", nullable = false)
  private String name;

  /**
   * Where this album's bytes live. Fixed at creation: moving an album between backends would mean
   * copying every original and derivative, and a half-moved album has no correct answer for a
   * presigned URL, so the API rejects the change rather than doing it badly. Defaults to the system
   * backend (the operator's MinIO) when the client does not pick one.
   */
  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "storage_backend_id", nullable = false)
  private StorageBackend storageBackend;

  @Column(name = "description")
  private String description;

  @Column(name = "created_at", nullable = false)
  private Instant createdAt;

  @Column(name = "updated_at")
  private Instant updatedAt;

  @Column(name = "display_order", nullable = false)
  private Integer displayOrder = 0;

  @Column(name = "share_token", unique = true, length = 128)
  private String shareToken;

  @Column(name = "analytics_paused", nullable = false)
  private boolean analyticsPaused = false;

  /**
   * Whether the share link works and subscribers may be notified. False on a freshly created album
   * — the owner publishes it once it holds what they want strangers to see. Every share-token
   * lookup on the public side goes through {@code findByShareTokenAndPublishedTrue}, so an
   * unpublished album is a 404 rather than an empty page.
   */
  @Column(name = "published", nullable = false)
  private boolean published = false;

  /**
   * When the album first went public, or null while it never has. Unpublishing leaves it set: it
   * records the first publication, and the "new albums" notifier uses it so a subscriber hears
   * about an album once, on the day it became visible rather than the day it was created.
   */
  @Column(name = "published_at")
  private Instant publishedAt;

  /**
   * Saved view for the map filter, as MapKit's CoordinateRegion: a centre plus a span in degrees
   * (the span is the zoom — smaller means closer in). All four are set together or all four are
   * null; null means the map frames every pin instead. See {@link
   * com.oglimmer.photoupload.model.MapView} for the validated form.
   */
  @Column(name = "map_center_lat")
  private Double mapCenterLat;

  @Column(name = "map_center_lng")
  private Double mapCenterLng;

  @Column(name = "map_span_lat")
  private Double mapSpanLat;

  @Column(name = "map_span_lng")
  private Double mapSpanLng;

  @OneToMany(mappedBy = "album", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
  private List<FileMetadata> files = new ArrayList<>();

  @PrePersist
  protected void onCreate() {
    if (createdAt == null) {
      createdAt = Instant.now();
    }
    if (updatedAt == null) {
      updatedAt = Instant.now();
    }
  }

  @PreUpdate
  protected void onUpdate() {
    updatedAt = Instant.now();
  }
}
