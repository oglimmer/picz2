/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BulkTagResponse {

  private boolean success;
  private String message;
  private String tagName;

  /**
   * Number of files whose tags actually changed (files already in the desired state are skipped).
   */
  private int updatedCount;
}
