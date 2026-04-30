/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConfigurationProperties(prefix = "storage.s3")
@Data
public class ObjectStorageProperties {

  /**
   * Master switch. When false, no S3 beans are created and the application falls back to the
   * filesystem code paths exactly as before. Lets us land the S3 client wiring before the
   * upload/processing/serve refactors, and lets local dev boot without MinIO.
   */
  private boolean enabled = false;

  /** Full URL including scheme (e.g. {@code http://minio.minio.svc.cluster.local:9000}). */
  private String endpoint;

  private String accessKey;

  private String secretKey;

  /** Bucket containing both {@code originals/} and {@code derivatives/} prefixes. */
  private String bucket = "photo-upload";

  /**
   * AWS SDK requires a region for signing even when talking to MinIO. {@code us-east-1} is the
   * conventional placeholder.
   */
  private String region = "us-east-1";

  /**
   * MinIO requires path-style addressing ({@code endpoint/bucket/key}); virtual-hosted style
   * ({@code bucket.endpoint/key}) needs DNS records that don't exist in-cluster.
   */
  private boolean pathStyleAccess = true;

  /**
   * If true, the bootstrapper creates the bucket on startup when it doesn't exist. Disable in
   * environments where bucket lifecycle is owned by the platform team.
   */
  private boolean autoCreateBucket = true;

  /** Default lifetime for presigned GET URLs handed back to clients. */
  private long presignSeconds = 3600;

  /**
   * Per-attempt HTTP timeout in seconds. 2s was too tight for large JPEG PUT-backs from the worker
   * (HEIC→JPEG conversion can produce 10-20 MB files). 30s gives headroom without holding threads
   * for an unreasonable time during a real MinIO outage.
   */
  private int apiCallAttemptTimeoutSeconds = 30;

  /**
   * Total wall-clock budget for a single S3 API call including SDK-internal retries. Kept at 2×
   * the attempt timeout so one retry is possible before giving up.
   */
  private int apiCallTimeoutSeconds = 60;
}
