/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.storage;

import com.oglimmer.photoupload.config.ObjectStorageProperties;
import com.oglimmer.photoupload.config.ResilienceConfig;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.security.SecretCipher;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import jakarta.annotation.PreDestroy;
import java.net.URI;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.checksums.RequestChecksumCalculation;
import software.amazon.awssdk.core.checksums.ResponseChecksumValidation;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/**
 * Builds and caches one {@link StorageClients} per {@link StorageBackend}.
 *
 * <p>The system default backend reuses the singleton {@code S3Client}/{@code S3Presigner} beans, so
 * its connection pool and breaker behave exactly as they did before per-album storage existed. A
 * user backend gets its own pair, built lazily on first use and kept until its row changes.
 *
 * <p>Cache invalidation is by content, not by event: the cached entry remembers a fingerprint of
 * the row's connection fields, and a mismatch rebuilds. That way an edit made by another pod (the
 * worker never sees the api pod's update) still takes effect on the next call rather than pinning
 * stale credentials until a restart.
 */
@Component
@ConditionalOnProperty(prefix = "storage.s3", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class StorageClientFactory {

  private final ObjectStorageProperties properties;
  private final S3Client systemS3;
  private final S3Presigner systemPresigner;
  private final CircuitBreakerRegistry breakerRegistry;
  private final SecretCipher secretCipher;

  private final Map<Long, CacheEntry> cache = new ConcurrentHashMap<>();

  private record CacheEntry(String fingerprint, StorageClients clients) {}

  /** Connection settings, resolved from either the row or {@code storage.s3.*}. */
  public record Settings(
      String endpoint,
      String region,
      String bucket,
      String accessKey,
      String secretKey,
      boolean pathStyleAccess) {}

  public StorageClients clientsFor(StorageBackend backend) {
    if (backend == null) {
      throw new StorageException("No storage backend on this album");
    }
    if (backend.isSystemDefault()) {
      return systemClients(backend.getId());
    }
    String fingerprint = fingerprint(backend);
    CacheEntry entry = cache.get(backend.getId());
    if (entry != null && entry.fingerprint().equals(fingerprint)) {
      return entry.clients();
    }
    synchronized (this) {
      entry = cache.get(backend.getId());
      if (entry != null && entry.fingerprint().equals(fingerprint)) {
        return entry.clients();
      }
      if (entry != null) {
        log.info("Storage backend {} changed; rebuilding its S3 client", backend.getId());
        closeQuietly(entry.clients());
      }
      StorageClients built =
          build(
              backend.getId(),
              settingsOf(backend),
              breakerRegistry.circuitBreaker("s3-backend-" + backend.getId()),
              false);
      cache.put(backend.getId(), new CacheEntry(fingerprint, built));
      return built;
    }
  }

  /** The call-facing handle for a backend: {@link BackendStorage} bound to its clients. */
  public BackendStorage storageFor(StorageBackend backend) {
    return new BackendStorage(clientsFor(backend), properties.getPresignSeconds());
  }

  /** Same, for clients the caller built itself via {@link #probeClients(Settings)}. */
  public BackendStorage storageFor(StorageClients clients) {
    return new BackendStorage(clients, properties.getPresignSeconds());
  }

  private StorageClients systemClients(Long backendId) {
    return new StorageClients(
        backendId,
        systemS3,
        systemPresigner,
        properties.getBucket(),
        breakerRegistry.circuitBreaker(ResilienceConfig.MINIO_BREAKER),
        true);
  }

  /**
   * Settings for a backend row. The system default deliberately reads from configuration instead of
   * the row so the cluster's MinIO credentials are never copied into the database.
   */
  public Settings settingsOf(StorageBackend backend) {
    if (backend.isSystemDefault()) {
      return new Settings(
          properties.getEndpoint(),
          properties.getRegion(),
          properties.getBucket(),
          properties.getAccessKey(),
          properties.getSecretKey(),
          properties.isPathStyleAccess());
    }
    return new Settings(
        backend.getEndpoint(),
        backend.getRegion(),
        backend.getBucket(),
        backend.getAccessKey(),
        secretCipher.decrypt(backend.getSecretKeyEncrypted()),
        backend.isPathStyleAccess());
  }

  /**
   * Clients for settings that are not persisted yet — used to prove a user's endpoint works before
   * their row is written. The caller owns the result and must call {@link #close(StorageClients)}.
   */
  public StorageClients probeClients(Settings settings) {
    return build(null, settings, breakerRegistry.circuitBreaker("s3-probe"), false);
  }

  private StorageClients build(
      Long backendId, Settings s, CircuitBreaker breaker, boolean systemDefault) {
    if (s.endpoint() == null || s.endpoint().isBlank()) {
      throw new StorageException("Storage backend has no endpoint");
    }
    if (s.bucket() == null || s.bucket().isBlank()) {
      throw new StorageException("Storage backend has no bucket");
    }
    StaticCredentialsProvider creds =
        StaticCredentialsProvider.create(AwsBasicCredentials.create(s.accessKey(), s.secretKey()));
    S3Configuration serviceConfig =
        S3Configuration.builder().pathStyleAccessEnabled(s.pathStyleAccess()).build();
    S3Client client =
        S3Client.builder()
            .endpointOverride(URI.create(s.endpoint()))
            .region(Region.of(s.region()))
            .credentialsProvider(creds)
            .serviceConfiguration(serviceConfig)
            .httpClientBuilder(
                ApacheHttpClient.builder()
                    // A user backend is one person's traffic, not the whole instance's, so it gets
                    // a quarter of the shared pool rather than a second full-sized one. Dozens of
                    // registered backends would otherwise each reserve 64 sockets.
                    .maxConnections(Math.max(8, properties.getMaxConnections() / 4))
                    .connectionAcquisitionTimeout(
                        Duration.ofSeconds(properties.getConnectionAcquisitionTimeoutSeconds())))
            .overrideConfiguration(
                ClientOverrideConfiguration.builder()
                    .apiCallAttemptTimeout(
                        Duration.ofSeconds(properties.getApiCallAttemptTimeoutSeconds()))
                    .apiCallTimeout(Duration.ofSeconds(properties.getApiCallTimeoutSeconds()))
                    .build())
            // Same reason as ObjectStorageConfig: MinIO (and several other gateways) still want
            // Content-MD5 on DeleteObjects and 400 without it.
            .requestChecksumCalculation(RequestChecksumCalculation.WHEN_REQUIRED)
            .responseChecksumValidation(ResponseChecksumValidation.WHEN_REQUIRED)
            .build();
    S3Presigner presigner =
        S3Presigner.builder()
            .endpointOverride(URI.create(s.endpoint()))
            .region(Region.of(s.region()))
            .credentialsProvider(creds)
            .serviceConfiguration(serviceConfig)
            .build();
    log.info(
        "Built S3 client for backend={} endpoint={} bucket={} pathStyle={}",
        backendId,
        s.endpoint(),
        s.bucket(),
        s.pathStyleAccess());
    return new StorageClients(backendId, client, presigner, s.bucket(), breaker, systemDefault);
  }

  private String fingerprint(StorageBackend b) {
    return String.join(
        "|",
        String.valueOf(b.getEndpoint()),
        String.valueOf(b.getRegion()),
        String.valueOf(b.getBucket()),
        String.valueOf(b.getAccessKey()),
        String.valueOf(b.isPathStyleAccess()),
        String.valueOf(b.getSecretKeyEncrypted()));
  }

  /** Drops a cached client, e.g. right after its row is deleted. Safe to call for unknown ids. */
  public void invalidate(Long backendId) {
    CacheEntry removed = cache.remove(backendId);
    if (removed != null) {
      closeQuietly(removed.clients());
    }
  }

  /** Closes clients the caller owns. Never closes the shared system-default beans. */
  public void close(StorageClients clients) {
    if (clients != null && !clients.systemDefault()) {
      closeQuietly(clients);
    }
  }

  private void closeQuietly(StorageClients clients) {
    try {
      clients.s3().close();
    } catch (RuntimeException e) {
      log.warn("Failed to close S3 client for backend {}: {}", clients.backendId(), e.getMessage());
    }
    try {
      clients.presigner().close();
    } catch (RuntimeException e) {
      log.warn("Failed to close presigner for backend {}: {}", clients.backendId(), e.getMessage());
    }
  }

  @PreDestroy
  void shutdown() {
    cache.values().forEach(e -> closeQuietly(e.clients()));
    cache.clear();
  }
}
