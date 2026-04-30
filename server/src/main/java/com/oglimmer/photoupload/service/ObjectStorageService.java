/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.ObjectStorageProperties;
import com.oglimmer.photoupload.exception.MinioUnavailableException;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import java.io.InputStream;
import java.net.URL;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

/**
 * Thin wrapper around the S3 SDK. Each upload uses {@link RequestBody#fromFile(Path)} which streams
 * directly from disk — never reading the whole file into the JVM heap. That is the entire reason
 * we bother with this layer instead of {@code S3Client.putObject(... InputStream ...)}.
 */
@Service
@ConditionalOnProperty(prefix = "storage.s3", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class ObjectStorageService {

  private final S3Client s3;
  private final S3Presigner presigner;
  private final ObjectStorageProperties properties;
  private final CircuitBreaker minioCircuitBreaker;

  /**
   * Run an SDK call through the breaker. {@link CallNotPermittedException} (breaker OPEN) is
   * translated to {@link MinioUnavailableException} so {@code GlobalExceptionHandler} can map it
   * to a 503 with {@code Retry-After}. Any other SDK exception bubbles up unchanged AND is
   * recorded as a failure by the breaker.
   */
  private <T> T withBreaker(Supplier<T> supplier) {
    try {
      return minioCircuitBreaker.executeSupplier(supplier);
    } catch (CallNotPermittedException e) {
      throw new MinioUnavailableException(
          "MinIO circuit breaker is OPEN; refusing call fast", e);
    }
  }

  private void runWithBreaker(Runnable r) {
    try {
      minioCircuitBreaker.executeRunnable(r);
    } catch (CallNotPermittedException e) {
      throw new MinioUnavailableException(
          "MinIO circuit breaker is OPEN; refusing call fast", e);
    }
  }

  /**
   * Upload a file. The {@code key} is the object name within the bucket (e.g. {@code
   * originals/abc.jpg}). {@code contentType} is stored as metadata so file-serve can hand it to
   * the browser without re-sniffing.
   */
  public void putFile(String key, Path source, String contentType) {
    PutObjectRequest.Builder req =
        PutObjectRequest.builder().bucket(properties.getBucket()).key(key);
    if (contentType != null && !contentType.isBlank()) {
      req.contentType(contentType);
    }
    runWithBreaker(() -> s3.putObject(req.build(), RequestBody.fromFile(source)));
    log.debug("S3 PUT s3://{}/{}", properties.getBucket(), key);
  }

  /**
   * Stream an {@link InputStream} of known length straight to S3. Used by the upload path so we
   * never have to materialise the upload to durable disk before PUTting it. The stream is read
   * exactly once — the SDK does not retry the body, so the caller must have already validated
   * inputs before calling.
   */
  public void putStream(String key, InputStream in, long contentLength, String contentType) {
    PutObjectRequest.Builder req =
        PutObjectRequest.builder().bucket(properties.getBucket()).key(key);
    if (contentType != null && !contentType.isBlank()) {
      req.contentType(contentType);
    }
    runWithBreaker(() -> s3.putObject(req.build(), RequestBody.fromInputStream(in, contentLength)));
    log.debug("S3 PUT s3://{}/{} ({} bytes, streamed)", properties.getBucket(), key, contentLength);
  }

  /**
   * Download an object to a local file. Used by the worker pipeline, which always operates on
   * local files (libvips, ffmpeg, etc).
   */
  public void getToFile(String key, Path destination) {
    GetObjectRequest req =
        GetObjectRequest.builder().bucket(properties.getBucket()).key(key).build();
    runWithBreaker(() -> s3.getObject(req, destination));
    log.debug("S3 GET s3://{}/{} → {}", properties.getBucket(), key, destination);
  }

  /** Stream an object straight to a caller (controller). Closes the {@link ResponseInputStream}. */
  public ResponseInputStream<GetObjectResponse> openStream(String key) {
    GetObjectRequest req =
        GetObjectRequest.builder().bucket(properties.getBucket()).key(key).build();
    return withBreaker(() -> s3.getObject(req));
  }

  /**
   * Stream a possibly-ranged object — forwards an HTTP {@code Range} header verbatim to S3 so
   * MinIO does the slicing, not the JVM. Callers should mirror the response's
   * {@link GetObjectResponse#contentRange()} and {@link GetObjectResponse#contentLength()} into
   * the outgoing HTTP response. {@code rangeHeader} may be null/blank to fetch the whole object.
   */
  public ResponseInputStream<GetObjectResponse> openStream(String key, String rangeHeader) {
    GetObjectRequest.Builder req =
        GetObjectRequest.builder().bucket(properties.getBucket()).key(key);
    if (rangeHeader != null && !rangeHeader.isBlank()) {
      req.range(rangeHeader);
    }
    return withBreaker(() -> s3.getObject(req.build()));
  }

  /** List every object key in the bucket, handling S3 pagination transparently. */
  public List<String> listKeys() {
    List<String> keys = new ArrayList<>();
    String continuationToken = null;
    do {
      final String token = continuationToken;
      ListObjectsV2Request.Builder req =
          ListObjectsV2Request.builder().bucket(properties.getBucket());
      if (token != null) {
        req.continuationToken(token);
      }
      ListObjectsV2Response page = withBreaker(() -> s3.listObjectsV2(req.build()));
      page.contents().forEach(obj -> keys.add(obj.key()));
      continuationToken = page.isTruncated() ? page.nextContinuationToken() : null;
    } while (continuationToken != null);
    return keys;
  }

  public void delete(String key) {
    runWithBreaker(
        () ->
            s3.deleteObject(
                DeleteObjectRequest.builder().bucket(properties.getBucket()).key(key).build()));
    log.debug("S3 DELETE s3://{}/{}", properties.getBucket(), key);
  }

  /**
   * Returns a time-limited URL the client can use to stream the object directly from MinIO,
   * bypassing the API pod. Used by file-serve once a request is authorised.
   */
  public URL presignGet(String key) {
    return presignGet(key, Duration.ofSeconds(properties.getPresignSeconds()));
  }

  public URL presignGet(String key, Duration ttl) {
    GetObjectPresignRequest req =
        GetObjectPresignRequest.builder()
            .signatureDuration(ttl)
            .getObjectRequest(
                GetObjectRequest.builder().bucket(properties.getBucket()).key(key).build())
            .build();
    return presigner.presignGetObject(req).url();
  }

  public String getBucket() {
    return properties.getBucket();
  }
}
