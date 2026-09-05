/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import com.oglimmer.photoupload.storage.S3Clients;
import com.oglimmer.photoupload.storage.StorageClientFactory;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.services.s3.S3Client;

/**
 * Wires AWS SDK v2 against the in-cluster MinIO. Beans are created only when {@code
 * storage.s3.enabled=true} so a developer running the app without MinIO doesn't need to set up fake
 * credentials. The builder itself lives in {@link S3Clients}, shared with the per-user backends.
 */
@Configuration
@ConditionalOnProperty(prefix = "storage.s3", name = "enabled", havingValue = "true")
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
