/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class FileServeInfo {

  private String mimeType;
  private String checksum;
  private Instant uploadedAt;
  private String filename;

  /**
   * Snapshot of the asset's processing state, so the serve layer can return 202 instead of a
   * not-yet-rendered original.
   */
  private ProcessingStatus processingStatus;

  /**
   * True when the size the caller asked for is actually populated in the DB. False when the caller
   * asked for a derivative (thumb/medium/large) but only the original is available — typically
   * because background processing hasn't finished yet.
   */
  private boolean derivativeReady;

  /** Object key of the variant being served, in the album's storage backend. */
  private String storageKey;

  /**
   * The album the asset belongs to. The serve layer needs it to pick the storage backend: albums
   * can sit on their owner's own S3, so a key alone does not say which endpoint holds it.
   */
  private Long albumId;
}
