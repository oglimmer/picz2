/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import java.net.URI;
import java.time.Duration;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/**
 * Wires AWS SDK v2 against the in-cluster MinIO. Beans are created only when {@code
 * storage.s3.enabled=true} so a developer running the app without MinIO doesn't need to set up
 * fake credentials.
 */
@Configuration
@ConditionalOnProperty(prefix = "storage.s3", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class ObjectStorageConfig {

  private final ObjectStorageProperties properties;

  private ClientOverrideConfiguration apiCallTimeouts() {
    return ClientOverrideConfiguration.builder()
        .apiCallAttemptTimeout(Duration.ofSeconds(properties.getApiCallAttemptTimeoutSeconds()))
        .apiCallTimeout(Duration.ofSeconds(properties.getApiCallTimeoutSeconds()))
        .build();
  }

  @Bean
  public S3Client s3Client() {
    log.info(
        "Building S3 client → endpoint={} bucket={} pathStyle={}",
        properties.getEndpoint(),
        properties.getBucket(),
        properties.isPathStyleAccess());
    return S3Client.builder()
        .endpointOverride(URI.create(properties.getEndpoint()))
        .region(Region.of(properties.getRegion()))
        .credentialsProvider(
            StaticCredentialsProvider.create(
                AwsBasicCredentials.create(properties.getAccessKey(), properties.getSecretKey())))
        .serviceConfiguration(
            S3Configuration.builder().pathStyleAccessEnabled(properties.isPathStyleAccess()).build())
        .httpClientBuilder(ApacheHttpClient.builder())
        .overrideConfiguration(apiCallTimeouts())
        .build();
  }

  @Bean
  public S3Presigner s3Presigner() {
    return S3Presigner.builder()
        .endpointOverride(URI.create(properties.getEndpoint()))
        .region(Region.of(properties.getRegion()))
        .credentialsProvider(
            StaticCredentialsProvider.create(
                AwsBasicCredentials.create(properties.getAccessKey(), properties.getSecretKey())))
        .serviceConfiguration(
            S3Configuration.builder().pathStyleAccessEnabled(properties.isPathStyleAccess()).build())
        .build();
  }
}
