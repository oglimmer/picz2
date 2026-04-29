/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import java.nio.file.Path;
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
  private Path filePath;
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

  /**
   * When non-null, the requested variant lives in object storage at this key, and {@link
   * #filePath} is null. Mutually exclusive with {@code filePath} — exactly one of the two is set.
   */
  private String storageKey;
}
