/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.storage;

import com.oglimmer.photoupload.exception.MinioUnavailableException;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import java.io.InputStream;
import java.net.URL;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.model.CopyObjectRequest;
import software.amazon.awssdk.services.s3.model.Delete;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectsRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectsResponse;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.MetadataDirective;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.ObjectIdentifier;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

/**
 * Thin wrapper around the S3 SDK, bound to one {@link StorageClients} (one album's backend). Each
 * upload uses {@link RequestBody#fromFile(Path)} which streams directly from disk — never reading
 * the whole file into the JVM heap. That is the entire reason we bother with this layer instead of
 * {@code S3Client.putObject(... InputStream ...)}.
 *
 * <p>Obtained from {@code ObjectStorageService.forAlbum(...)} / {@code forFile(...)}; never
 * constructed by callers, because picking the wrong backend silently writes an album's bytes
 * somewhere its owner cannot read them.
 */
@Slf4j
public class BackendStorage {

  private final StorageClients clients;
  private final long defaultPresignSeconds;

  BackendStorage(StorageClients clients, long defaultPresignSeconds) {
    this.clients = clients;
    this.defaultPresignSeconds = defaultPresignSeconds;
  }

  private String bucket() {
    return clients.bucket();
  }

  /**
   * Run an SDK call through this backend's breaker. {@link CallNotPermittedException} (breaker
   * OPEN) is translated to {@link MinioUnavailableException} so {@code GlobalExceptionHandler} can
   * map it to a 503 with {@code Retry-After}. Any other SDK exception bubbles up unchanged AND is
   * recorded as a failure by the breaker.
   */
  private <T> T withBreaker(Supplier<T> supplier) {
    try {
      return clients.breaker().executeSupplier(supplier);
    } catch (CallNotPermittedException e) {
      throw new MinioUnavailableException(
          "Storage backend " + clients.backendId() + " circuit breaker is OPEN; refusing call fast",
          e);
    }
  }

  private void runWithBreaker(Runnable r) {
    try {
      clients.breaker().executeRunnable(r);
    } catch (CallNotPermittedException e) {
      throw new MinioUnavailableException(
          "Storage backend " + clients.backendId() + " circuit breaker is OPEN; refusing call fast",
          e);
    }
  }

  /**
   * Upload a file. The {@code key} is the object name within the bucket (e.g. {@code
   * originals/abc.jpg}). {@code contentType} is stored as metadata so file-serve can hand it to the
   * browser without re-sniffing.
   */
  public void putFile(String key, Path source, String contentType) {
    PutObjectRequest.Builder req = PutObjectRequest.builder().bucket(bucket()).key(key);
    if (contentType != null && !contentType.isBlank()) {
      req.contentType(contentType);
    }
    runWithBreaker(() -> clients.s3().putObject(req.build(), RequestBody.fromFile(source)));
    log.debug("S3 PUT s3://{}/{}", bucket(), key);
  }

  /**
   * Stream an {@link InputStream} of known length straight to S3. Used by the upload path so we
   * never have to materialise the upload to durable disk before PUTting it. The stream is read
   * exactly once — the SDK does not retry the body, so the caller must have already validated
   * inputs before calling.
   */
  public void putStream(String key, InputStream in, long contentLength, String contentType) {
    PutObjectRequest.Builder req = PutObjectRequest.builder().bucket(bucket()).key(key);
    if (contentType != null && !contentType.isBlank()) {
      req.contentType(contentType);
    }
    runWithBreaker(
        () -> clients.s3().putObject(req.build(), RequestBody.fromInputStream(in, contentLength)));
    log.debug("S3 PUT s3://{}/{} ({} bytes, streamed)", bucket(), key, contentLength);
  }

  /**
   * Download an object to a local file. Used by the worker pipeline, which always operates on local
   * files (libvips, ffmpeg, etc).
   */
  public void getToFile(String key, Path destination) {
    GetObjectRequest req = GetObjectRequest.builder().bucket(bucket()).key(key).build();
    runWithBreaker(() -> clients.s3().getObject(req, destination));
    log.debug("S3 GET s3://{}/{} → {}", bucket(), key, destination);
  }

  /** Stream an object straight to a caller (controller). Closes the {@link ResponseInputStream}. */
  public ResponseInputStream<GetObjectResponse> openStream(String key) {
    GetObjectRequest req = GetObjectRequest.builder().bucket(bucket()).key(key).build();
    return withBreaker(() -> clients.s3().getObject(req));
  }

  /**
   * Stream a possibly-ranged object — forwards an HTTP {@code Range} header verbatim to S3 so the
   * backend does the slicing, not the JVM. Callers should mirror the response's {@link
   * GetObjectResponse#contentRange()} and {@link GetObjectResponse#contentLength()} into the
   * outgoing HTTP response. {@code rangeHeader} may be null/blank to fetch the whole object.
   */
  public ResponseInputStream<GetObjectResponse> openStream(String key, String rangeHeader) {
    GetObjectRequest.Builder req = GetObjectRequest.builder().bucket(bucket()).key(key);
    if (rangeHeader != null && !rangeHeader.isBlank()) {
      req.range(rangeHeader);
    }
    return withBreaker(() -> clients.s3().getObject(req.build()));
  }

  /**
   * List object keys under {@code prefix} whose {@code LastModified} is strictly before {@code
   * cutoff}. Used by the retention CronJob's TUS-cleanup pass — the S3 ListObjectsV2 API doesn't
   * support a date filter, so we page through and filter client-side. Cheap regardless: pages are
   * 1000 keys each, and the {@code tus-uploads/} prefix is short-lived in normal operation
   * (post-finish hook deletes the object) so the prefix is usually nearly empty.
   */
  public List<String> listKeysOlderThan(String prefix, Instant cutoff) {
    List<String> keys = new ArrayList<>();
    String continuationToken = null;
    do {
      final String token = continuationToken;
      ListObjectsV2Request.Builder req =
          ListObjectsV2Request.builder().bucket(bucket()).prefix(prefix);
      if (token != null) {
        req.continuationToken(token);
      }
      ListObjectsV2Response page = withBreaker(() -> clients.s3().listObjectsV2(req.build()));
      for (S3Object obj : page.contents()) {
        if (obj.lastModified() != null && obj.lastModified().isBefore(cutoff)) {
          keys.add(obj.key());
        }
      }
      continuationToken = page.isTruncated() ? page.nextContinuationToken() : null;
    } while (continuationToken != null);
    return keys;
  }

  /**
   * Key → size for everything under {@code prefix}. Used by the storage-usage backfill, which has
   * to learn what objects written before the byte columns existed actually cost; the sizes come
   * back in the same listing as the keys, so this is no more expensive than {@link #listKeys()}.
   */
  public Map<String, Long> listKeySizes(String prefix) {
    Map<String, Long> sizes = new HashMap<>();
    String continuationToken = null;
    do {
      final String token = continuationToken;
      ListObjectsV2Request.Builder req =
          ListObjectsV2Request.builder().bucket(bucket()).prefix(prefix);
      if (token != null) {
        req.continuationToken(token);
      }
      ListObjectsV2Response page = withBreaker(() -> clients.s3().listObjectsV2(req.build()));
      for (S3Object obj : page.contents()) {
        sizes.put(obj.key(), obj.size() == null ? 0L : obj.size());
      }
      continuationToken = page.isTruncated() ? page.nextContinuationToken() : null;
    } while (continuationToken != null);
    return sizes;
  }

  /** List every object key in the bucket, handling S3 pagination transparently. */
  public List<String> listKeys() {
    List<String> keys = new ArrayList<>();
    String continuationToken = null;
    do {
      final String token = continuationToken;
      ListObjectsV2Request.Builder req = ListObjectsV2Request.builder().bucket(bucket());
      if (token != null) {
        req.continuationToken(token);
      }
      ListObjectsV2Response page = withBreaker(() -> clients.s3().listObjectsV2(req.build()));
      page.contents().forEach(obj -> keys.add(obj.key()));
      continuationToken = page.isTruncated() ? page.nextContinuationToken() : null;
    } while (continuationToken != null);
    return keys;
  }

  /**
   * True when the bucket holds this key. Uses {@code HeadObject}, which fetches metadata only — no
   * object bytes cross the wire. A missing key answers false rather than throwing; any other S3
   * fault still propagates, because "cannot tell" must not read as "not there".
   */
  public boolean exists(String key) {
    // The 404 is caught INSIDE the breaker's supplier on purpose. Catching it outside made every
    // "not there" answer count as a storage failure, and enough of them in the sliding window
    // tripped the breaker OPEN — which then failed unrelated storage calls for ten seconds.
    // A key that is legitimately absent is a successful call, not a fault.
    return withBreaker(
        () -> {
          try {
            clients.s3().headObject(HeadObjectRequest.builder().bucket(bucket()).key(key).build());
            return true;
          } catch (NoSuchKeyException e) {
            return false;
          } catch (S3Exception e) {
            if (e.statusCode() == 404) {
              return false;
            }
            throw e;
          }
        });
  }

  public void delete(String key) {
    runWithBreaker(
        () ->
            clients
                .s3()
                .deleteObject(DeleteObjectRequest.builder().bucket(bucket()).key(key).build()));
    log.debug("S3 DELETE s3://{}/{}", bucket(), key);
  }

  /**
   * Server-side copy within the same bucket. The storage backend performs the copy without bytes
   * leaving it, so this is the cheap rename we use after a TUS upload finalises (move from {@code
   * tus-uploads/{uuid}} to {@code originals/{stored_filename}} per D24/D25).
   *
   * <p>Only valid when source and destination live in the SAME backend. Crossing backends needs
   * {@code ObjectStorageService.transfer(...)}, which streams the bytes through the JVM.
   *
   * <p>{@code contentType} is set on the destination object only when non-blank — passing null
   * keeps the source's content-type via {@link MetadataDirective#COPY} (the default), so
   * existing-bucket COPYs (e.g. from another module) don't accidentally clobber metadata.
   */
  public void copy(String srcKey, String dstKey, String contentType) {
    CopyObjectRequest.Builder req =
        CopyObjectRequest.builder()
            .sourceBucket(bucket())
            .sourceKey(srcKey)
            .destinationBucket(bucket())
            .destinationKey(dstKey);
    if (contentType != null && !contentType.isBlank()) {
      req.metadataDirective(MetadataDirective.REPLACE).contentType(contentType);
    }
    runWithBreaker(() -> clients.s3().copyObject(req.build()));
    log.debug("S3 COPY s3://{}/{} → s3://{}/{}", bucket(), srcKey, bucket(), dstKey);
  }

  /**
   * Bulk delete using the {@code DeleteObjects} API. Splits the input into batches of up to 1000
   * keys (the S3 per-call limit). Per-key errors reported by S3 are logged but do not throw — the
   * caller has already orphaned the metadata rows, so a half-deleted set of S3 objects is purged
   * out-of-band by the orphan sweeper rather than aborting the request.
   */
  public void deleteKeys(Collection<String> keys) {
    if (keys == null || keys.isEmpty()) {
      return;
    }
    final int batchSize = 1000;
    List<ObjectIdentifier> batch = new ArrayList<>(batchSize);
    for (String key : keys) {
      if (key == null || key.isBlank()) {
        continue;
      }
      batch.add(ObjectIdentifier.builder().key(key).build());
      if (batch.size() == batchSize) {
        deleteObjectsBatch(batch);
        batch = new ArrayList<>(batchSize);
      }
    }
    if (!batch.isEmpty()) {
      deleteObjectsBatch(batch);
    }
  }

  private void deleteObjectsBatch(List<ObjectIdentifier> batch) {
    DeleteObjectsRequest req =
        DeleteObjectsRequest.builder()
            .bucket(bucket())
            .delete(Delete.builder().objects(batch).quiet(true).build())
            .build();
    DeleteObjectsResponse resp = withBreaker(() -> clients.s3().deleteObjects(req));
    if (resp.hasErrors() && !resp.errors().isEmpty()) {
      resp.errors()
          .forEach(
              e ->
                  log.warn(
                      "S3 batch DELETE error key={} code={} message={}",
                      e.key(),
                      e.code(),
                      e.message()));
    }
    log.debug("S3 batch DELETE {} keys from s3://{}", batch.size(), bucket());
  }

  /**
   * Returns a time-limited URL the client can use to stream the object directly from the backend,
   * bypassing the API pod. Used by file-serve once a request is authorised.
   */
  public URL presignGet(String key) {
    return presignGet(key, Duration.ofSeconds(defaultPresignSeconds));
  }

  public URL presignGet(String key, Duration ttl) {
    GetObjectPresignRequest req =
        GetObjectPresignRequest.builder()
            .signatureDuration(ttl)
            .getObjectRequest(GetObjectRequest.builder().bucket(bucket()).key(key).build())
            .build();
    return clients.presigner().presignGetObject(req).url();
  }

  public String getBucket() {
    return bucket();
  }

  public Long getBackendId() {
    return clients.backendId();
  }

  public boolean isSystemDefault() {
    return clients.systemDefault();
  }
}
