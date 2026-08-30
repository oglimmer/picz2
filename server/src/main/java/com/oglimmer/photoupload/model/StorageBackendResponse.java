/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * A storage backend as the client sees it. The secret key is never included, in any form — not
 * masked, not truncated. The access key is, because it is an identifier rather than a credential
 * and the user needs it to tell two of their own buckets apart.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class StorageBackendResponse {

  private Long id;

  private String name;

  /** True for the instance's own storage, which every user can select but nobody can edit. */
  private boolean systemDefault;

  private String endpoint;

  private String region;

  private String bucket;

  private String accessKey;

  private boolean pathStyleAccess;

  /**
   * How many albums already store bytes here. Non-zero means the row cannot be deleted, and the
   * clients use it to explain why rather than just greying the button out.
   */
  private long albumCount;

  private Instant createdAt;

  /**
   * Bytes the user currently keeps here, and their allowance. Both null for a user's own storage:
   * only the instance's own disk is metered, because only that one costs the operator anything.
   */
  private Long usedBytes;

  private Long quotaBytes;
}
