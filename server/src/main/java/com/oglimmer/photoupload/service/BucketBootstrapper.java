/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.ObjectStorageProperties;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.BucketAlreadyOwnedByYouException;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.HeadBucketRequest;
import software.amazon.awssdk.services.s3.model.NoSuchBucketException;
import software.amazon.awssdk.services.s3.model.S3Exception;

/**
 * Verifies the configured bucket exists at startup. When {@code autoCreateBucket=true} (default),
 * the bucket is created if missing — convenient for fresh environments. When false, a missing
 * bucket fails fast so a misconfigured deploy doesn't silently lose uploads.
 */
@Component
@ConditionalOnProperty(prefix = "storage.s3", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class BucketBootstrapper {

  private final S3Client s3;
  private final ObjectStorageProperties properties;

  @PostConstruct
  void ensureBucket() {
    String bucket = properties.getBucket();
    try {
      s3.headBucket(HeadBucketRequest.builder().bucket(bucket).build());
      log.info("Object-storage bucket '{}' is reachable", bucket);
      return;
    } catch (NoSuchBucketException e) {
      // Falls through to create-or-fail below.
    } catch (S3Exception e) {
      if (e.statusCode() != 404) {
        throw e;
      }
    }

    if (!properties.isAutoCreateBucket()) {
      throw new IllegalStateException(
          "Bucket '" + bucket + "' does not exist and storage.s3.auto-create-bucket=false");
    }

    try {
      s3.createBucket(CreateBucketRequest.builder().bucket(bucket).build());
      log.info("Created object-storage bucket '{}'", bucket);
    } catch (BucketAlreadyOwnedByYouException ignore) {
      log.info("Bucket '{}' already owned by us (created concurrently)", bucket);
    }
  }
}
