/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * The signed-in user's standing with the instance's own storage, for the clients' "storage full"
 * banner. Small on purpose: the clients poll it, so it must not decrypt anything, list any bucket
 * or count anything the banner does not need. The full per-backend picture stays on {@code GET
 * /api/storage-backends}.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class StorageUsageResponse {

  /** Bytes the user currently keeps on the instance's own storage. */
  private long usedBytes;

  /** Their allowance. Zero means a frozen account, which is full by definition. */
  private long quotaBytes;

  /** {@code max(0, quotaBytes - usedBytes)}. */
  private long remainingBytes;

  /**
   * True while uploads to albums on the instance's own storage are refused with 507. The clients
   * show a banner exactly while this is true — they must not decide it themselves from the two
   * numbers, so that the rule lives in one place.
   */
  private boolean full;
}
