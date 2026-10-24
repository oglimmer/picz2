/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * How often one visitor looked at one photo full screen on the public share page (D90).
 *
 * <p>Written only through {@code ImageViewCountRepository.addViews}, an upsert that adds to the
 * counters; nothing loads and saves this entity. It exists so the table is validated at startup
 * like every other one.
 */
@Entity
@Table(name = "image_view_counts")
@Data
@NoArgsConstructor
public class ImageViewCount {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "album_id", nullable = false)
  private Long albumId;

  @Column(name = "file_metadata_id", nullable = false)
  private Long fileMetadataId;

  @Column(name = "visitor_id", nullable = false)
  private String visitorId;

  /** Clicked in the grid or on the map to open it full screen. */
  @Column(name = "opens", nullable = false)
  private Integer opens = 0;

  /** Reached with next/previous while already full screen. */
  @Column(name = "walk_ins", nullable = false)
  private Integer walkIns = 0;

  @Column(name = "first_seen_at", nullable = false)
  private Instant firstSeenAt;

  @Column(name = "last_seen_at", nullable = false)
  private Instant lastSeenAt;
}
