/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "file_metadata")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class FileMetadata {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "original_name", nullable = false)
  private String originalName;

  @Column(name = "stored_filename", nullable = false, unique = true)
  private String storedFilename;

  @Column(name = "file_size", nullable = false)
  private Long fileSize;

  @Column(name = "mime_type")
  private String mimeType;

  // Nullable since Phase 6 / Gap 4-finish: the retention CronJob purges originals once derivatives
  // exist and the row is older than `retention.original-days`, then sets file_path = NULL. Rows
  // with file_path = NULL are still served via their thumb/medium/large derivatives.
  @Column(name = "file_path")
  private String filePath;

  @Column(name = "uploaded_at", nullable = false)
  private Instant uploadedAt;

  @Column(name = "checksum")
  private String checksum;

  @Column(name = "content_id")
  private String contentId;

  @Column(name = "width")
  private Integer width;

  @Column(name = "height")
  private Integer height;

  @Column(name = "duration")
  private Long duration;

  @Column(name = "exif_date_time_original")
  private Instant exifDateTimeOriginal;

  @Column(name = "rotation", nullable = false)
  private Integer rotation = 0;

  @Column(name = "display_order", nullable = false)
  private Integer displayOrder = 0;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "album_id", nullable = false)
  private Album album;

  @Column(name = "public_token", unique = true, length = 64)
  private String publicToken;

  @Column(name = "thumbnail_path")
  private String thumbnailPath;

  @Column(name = "medium_path")
  private String mediumPath;

  @Column(name = "large_path")
  private String largePath;

  @Column(name = "transcoded_video_path")
  private String transcodedVideoPath;

  @Enumerated(EnumType.STRING)
  @Column(name = "processing_status", nullable = false, length = 32)
  private ProcessingStatus processingStatus = ProcessingStatus.QUEUED;

  @Column(name = "processing_attempts", nullable = false)
  private Integer processingAttempts = 0;

  @Column(name = "processing_error", columnDefinition = "TEXT")
  private String processingError;

  @Column(name = "processing_completed_at")
  private Instant processingCompletedAt;

  @OneToMany(mappedBy = "fileMetadata", cascade = CascadeType.ALL, orphanRemoval = true)
  private List<ImageTag> imageTags = new ArrayList<>();

  @PrePersist
  protected void onCreate() {
    if (uploadedAt == null) {
      uploadedAt = Instant.now();
    }
    if (publicToken == null || publicToken.isBlank()) {
      byte[] bytes = new byte[24]; // 48 hex chars
      new SecureRandom().nextBytes(bytes);
      publicToken = HexFormat.of().formatHex(bytes);
    }
  }
}
