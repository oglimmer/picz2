/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.util.List;
import lombok.Builder;
import lombok.Data;

/**
 * Answer to {@code GET /api/sync/uploaded-content-ids}. Deliberately the same shape as {@link
 * SyncChecksumsResponse} so a client can treat the two reconciliation sources identically.
 */
@Data
@Builder
public class SyncContentIdsResponse {

  private boolean success;
  private List<String> contentIds;
  private int count;
}
