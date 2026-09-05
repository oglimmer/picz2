/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.testsupport;

import org.springframework.test.context.DynamicPropertyRegistry;
import org.testcontainers.containers.MinIOContainer;

/**
 * A throwaway MinIO for the Docker-gated Spring context tests. {@code BucketBootstrapper} does a
 * {@code HeadBucket} at startup, so every full context needs a reachable S3 endpoint — without one
 * the S3 client refuses to build ("URI scheme of endpointOverride must not be null") and the
 * context never starts. Declare the container with {@code @Container} and wire its coordinates in a
 * {@code @DynamicPropertySource} method via {@link #register}.
 */
public final class TestObjectStorage {

  private TestObjectStorage() {}

  public static MinIOContainer newMinio() {
    return new MinIOContainer("minio/minio:latest").withReuse(false);
  }

  public static void register(DynamicPropertyRegistry registry, MinIOContainer minio) {
    registry.add("storage.s3.endpoint", minio::getS3URL);
    registry.add("storage.s3.access-key", minio::getUserName);
    registry.add("storage.s3.secret-key", minio::getPassword);
    registry.add("storage.s3.bucket", () -> "photo-upload-test");
    registry.add("storage.s3.auto-create-bucket", () -> "true");
  }
}
