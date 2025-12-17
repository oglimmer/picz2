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
import jakarta.persistence.OrderBy;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "slideshow_recordings")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class SlideshowRecording {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "album_id", nullable = false)
  private Album album;

  @Column(name = "filter_tag")
  private String filterTag;

  @Column(name = "language", length = 50)
  private String language;

  @Column(name = "audio_filename", nullable = false, length = 512)
  private String audioFilename;

  @Column(name = "audio_path", nullable = false, length = 1024)
  private String audioPath;

  @Column(name = "public_token", unique = true, length = 64)
  private String publicToken;

  @Column(name = "duration_ms", nullable = false)
  private Long durationMs;

  @Column(name = "created_at", nullable = false)
  private Instant createdAt;

  @OneToMany(mappedBy = "recording", cascade = CascadeType.ALL, orphanRemoval = true)
  @OrderBy("sequenceOrder ASC")
  private List<SlideshowRecordingImage> images = new ArrayList<>();

  @PrePersist
  protected void onCreate() {
    if (createdAt == null) {
      createdAt = Instant.now();
    }
  }
}
