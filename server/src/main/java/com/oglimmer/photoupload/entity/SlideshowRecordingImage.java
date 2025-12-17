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
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "slideshow_recording_images")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class SlideshowRecordingImage {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "recording_id", nullable = false)
  private SlideshowRecording recording;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "file_id", nullable = false)
  private FileMetadata file;

  @Column(name = "start_time_ms", nullable = false)
  private Long startTimeMs;

  @Column(name = "duration_ms", nullable = false)
  private Long durationMs;

  @Column(name = "sequence_order", nullable = false)
  private Integer sequenceOrder;
}
