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
 * A section marker inside the presentation view of one (album, tag) pair. The group starts at
 * {@link #startFile} and — when the tag-filtered file list is walked in {@code display_order} —
 * owns every image up to the next group's start. There is deliberately no explicit ordering column:
 * order is derived from the images the user already curates.
 */
@Entity
@Table(
    name = "presentation_groups",
    uniqueConstraints = {
      @UniqueConstraint(
          name = "uk_pg_album_tag_start",
          columnNames = {"album_id", "tag_id", "start_file_id"})
    })
@Data
@NoArgsConstructor
@AllArgsConstructor
public class PresentationGroup {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY, optional = false)
  @JoinColumn(name = "album_id", nullable = false)
  private Album album;

  @ManyToOne(fetch = FetchType.EAGER, optional = false)
  @JoinColumn(name = "tag_id", nullable = false)
  private Tag tag;

  @ManyToOne(fetch = FetchType.EAGER, optional = false)
  @JoinColumn(name = "start_file_id", nullable = false)
  private FileMetadata startFile;

  @Column(name = "label", nullable = false, length = 120)
  private String label;

  @Column(name = "body_text", length = 4000)
  private String bodyText;

  @Column(name = "created_at", nullable = false)
  private Instant createdAt;

  @Column(name = "updated_at")
  private Instant updatedAt;

  @PrePersist
  protected void onCreate() {
    if (createdAt == null) {
      createdAt = Instant.now();
    }
  }

  @PreUpdate
  protected void onUpdate() {
    updatedAt = Instant.now();
  }
}
