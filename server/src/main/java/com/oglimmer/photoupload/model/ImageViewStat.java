/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/** One photo in the owner's "most looked-at" list (D90). */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ImageViewStat {

  private Long fileId;

  /** For the thumbnail through {@code /api/i/{token}}; this list is owner-only. */
  private String publicToken;

  private String originalName;
  private String mimeType;
  private long opens;
  private long walkIns;

  /** Distinct visitors who looked at it full screen at least once. */
  private long viewers;
}
