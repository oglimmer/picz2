/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.storage;

import com.oglimmer.photoupload.config.ObjectStorageProperties;
import java.net.URI;
import java.time.Duration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.checksums.RequestChecksumCalculation;
import software.amazon.awssdk.core.checksums.ResponseChecksumValidation;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;

/**
 * The one recipe for an {@link S3Client} in this app. The instance's own MinIO (a Spring bean) and
 * every user-registered backend (built lazily by {@link StorageClientFactory}) used to be two
 * copies of the same builder chain; a setting fixed in one was silently missing from the other.
 */
public final class S3Clients {

  private S3Clients() {}

  /**
   * @param settings endpoint, region, bucket and credentials
   * @param maxConnections size of the Apache pool for this client
   * @param timeouts per-attempt / per-call budgets and the acquisition timeout, read from {@code
   *     storage.s3.*} for every backend alike
   */
  public static S3Client build(
      StorageClientFactory.Settings settings,
      int maxConnections,
      ObjectStorageProperties timeouts) {
    return S3Client.builder()
        .endpointOverride(URI.create(settings.endpoint()))
        .region(Region.of(settings.region()))
        .credentialsProvider(
            StaticCredentialsProvider.create(
                AwsBasicCredentials.create(settings.accessKey(), settings.secretKey())))
        .serviceConfiguration(
            S3Configuration.builder().pathStyleAccessEnabled(settings.pathStyleAccess()).build())
        .httpClientBuilder(
            ApacheHttpClient.builder()
                .maxConnections(maxConnections)
                .connectionAcquisitionTimeout(
                    Duration.ofSeconds(timeouts.getConnectionAcquisitionTimeoutSeconds())))
        .overrideConfiguration(
            ClientOverrideConfiguration.builder()
                .apiCallAttemptTimeout(
                    Duration.ofSeconds(timeouts.getApiCallAttemptTimeoutSeconds()))
                .apiCallTimeout(Duration.ofSeconds(timeouts.getApiCallTimeoutSeconds()))
                .build())
        // SDK v2.30+ defaults to Flexible Checksums (CRC32) and stops sending Content-MD5 on
        // DeleteObjects. MinIO (and several other gateways) still require Content-MD5 for the
        // multi-object delete and 400 without it. WHEN_REQUIRED restores the pre-2.30 behaviour.
        .requestChecksumCalculation(RequestChecksumCalculation.WHEN_REQUIRED)
        .responseChecksumValidation(ResponseChecksumValidation.WHEN_REQUIRED)
        .build();
  }
}
