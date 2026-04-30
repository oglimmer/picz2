/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class FileInfo {

  private Long id;
  private String originalName;
  private String filename;
  private String publicToken;
  private long size;
  private String mimetype;
  private String path;
  private Instant uploadedAt;
  private Instant exifDateTimeOriginal;
  private Integer rotation;
  private Integer displayOrder;
  private List<String> tags = new ArrayList<>();
  private Long albumId;
  private String albumName;
  private ProcessingStatus processingStatus;

  /**
   * False when the original was purged from object storage by the retention CronJob (Phase 6 /
   * Gap 4-finish). Used by the UI to hide rotate/download-original actions; the gallery itself
   * keeps working from derivatives.
   */
  private boolean originalAvailable;
}
