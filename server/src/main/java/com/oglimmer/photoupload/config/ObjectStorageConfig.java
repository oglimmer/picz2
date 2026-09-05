/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import com.oglimmer.photoupload.storage.S3Clients;
import com.oglimmer.photoupload.storage.StorageClientFactory;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.services.s3.S3Client;

/**
 * Wires AWS SDK v2 against the instance's own MinIO. Object storage is the only storage there is
 * (D77) — local dev runs MinIO from compose, production from the cluster — so these beans are
 * unconditional. The builder itself lives in {@link S3Clients}, shared with the per-user backends.
 */
@Configuration
@RequiredArgsConstructor
@Slf4j
public class ObjectStorageConfig {

  private final ObjectStorageProperties properties;

  @Bean
  public S3Client s3Client() {
    log.info(
        "Building S3 client → endpoint={} bucket={} pathStyle={}",
        properties.getEndpoint(),
        properties.getBucket(),
        properties.isPathStyleAccess());
    StorageClientFactory.Settings settings =
        new StorageClientFactory.Settings(
            properties.getEndpoint(),
            properties.getRegion(),
            properties.getBucket(),
            properties.getAccessKey(),
            properties.getSecretKey(),
            properties.isPathStyleAccess());
    return S3Clients.build(settings, properties.getMaxConnections(), properties);
  }
}
