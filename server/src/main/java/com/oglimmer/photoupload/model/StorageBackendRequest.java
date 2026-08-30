/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/** What a user sends to register or edit their own S3-compatible storage. */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class StorageBackendRequest {

  /** Label shown in the album-create picker. Unique per user. */
  private String name;

  /** Full URL including scheme, e.g. {@code https://s3.eu-central-1.amazonaws.com}. */
  private String endpoint;

  private String region;

  private String bucket;

  private String accessKey;

  /**
   * Write-only. Absent on every response, and on an update an absent value means "keep the stored
   * one" — so editing a bucket name does not force the user to re-type their secret.
   */
  private String secretKey;

  /**
   * Defaults to true when omitted: MinIO, Garage, Ceph and most self-hosted gateways require
   * path-style addressing, and self-hosting is what this feature is for.
   */
  private Boolean pathStyleAccess;
}
