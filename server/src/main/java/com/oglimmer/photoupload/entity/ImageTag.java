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
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(
    name = "image_tags",
    uniqueConstraints = {
      @UniqueConstraint(
          name = "uk_file_tag",
          columnNames = {"file_metadata_id", "tag_id"})
    })
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ImageTag {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "file_metadata_id", nullable = false)
  private FileMetadata fileMetadata;

  @ManyToOne(fetch = FetchType.EAGER)
  @JoinColumn(name = "tag_id", nullable = false)
  private Tag tag;

  @Column(name = "tagged_at", nullable = false)
  private Instant taggedAt;

  @PrePersist
  protected void onCreate() {
    if (taggedAt == null) {
      taggedAt = Instant.now();
    }
  }
}
