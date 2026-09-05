/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.FileServeInfo;
import com.oglimmer.photoupload.service.FileStorageService;
import com.oglimmer.photoupload.service.ObjectStorageService;
import com.oglimmer.photoupload.storage.BackendStorage;
import com.oglimmer.photoupload.util.RangeRequestHandler;
import java.io.OutputStream;
import java.time.Instant;
import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/i")
@Slf4j
public class ImageServeController {

  private static final String RETRY_AFTER_SECONDS = "2";

  private final FileStorageService fileStorageService;
  // Optional: only populated when storage.s3.enabled=true. Older deployments without MinIO still
  // boot; serving an S3-keyed row in that mode is impossible by definition.
  private final Optional<ObjectStorageService> objectStorage;

  public ImageServeController(
      FileStorageService fileStorageService, Optional<ObjectStorageService> objectStorage) {
    this.fileStorageService = fileStorageService;
    this.objectStorage = objectStorage;
  }

  /**
   * Serves a ranged GET, which is how AVPlayer (iOS) and Safari fetch video: they open with {@code
   * Range: bytes=0-1} and will not seek in a response that cannot answer one.
   *
   * <p>This is a **separate handler** rather than a branch inside {@link #downloadFileByToken}, and
   * the declared return type matters. {@code StreamingResponseBodyReturnValueHandler} only claims a
   * return value when the declared type is {@code ResponseEntity<StreamingResponseBody>}; a {@code
   * ResponseEntity<?>} falls through to {@code HttpEntityMethodProcessor}, which looks for a
   * message converter for the lambda's class, finds none, and 500s with "No converter for
   * [...$$Lambda] with preset Content-Type 'video/mp4'". Spring routes here ahead of the wildcard
   * mapping because {@code headers = "Range"} is the more specific condition.
   */
  @GetMapping(value = "/{token}", headers = HttpHeaders.RANGE)
  public ResponseEntity<StreamingResponseBody> streamRangeByToken(
      @PathVariable String token,
      @RequestParam(value = "size", required = false) String size,
      @RequestHeader(HttpHeaders.RANGE) String rangeHeader,
      WebRequest webRequest) {
    try {
      FileServeInfo fileInfo = fileStorageService.getFileServeInfoByPublicToken(token, size);

      if (!fileInfo.isDerivativeReady()
          && fileInfo.getProcessingStatus() != ProcessingStatus.DONE) {
        return ResponseEntity.status(HttpStatus.ACCEPTED)
            .header(HttpHeaders.RETRY_AFTER, RETRY_AFTER_SECONDS)
            .cacheControl(CacheControl.noStore())
            .build();
      }

      if (isNotModified(webRequest, fileInfo)) {
        return null; // webRequest already set 304 + validators on the response
      }

      if (fileInfo.getStorageKey() != null) {
        return serveRangeFromObjectStorage(fileInfo, rangeHeader);
      }
      return RangeRequestHandler.serveFileWithRangeSupport(
          fileInfo.getFilePath(),
          rangeHeader,
          fileInfo.getMimeType() != null
              ? fileInfo.getMimeType()
              : MediaType.APPLICATION_OCTET_STREAM_VALUE,
          safeFilenameForKey(fileInfo));
    } catch (RuntimeException e) {
      // Already the right shape for GlobalExceptionHandler: 404 for a missing token, 410 for a
      // retention-purged original, 503 for an open MinIO breaker. Wrapping any of these used to
      // collapse them all into a 500.
      throw e;
    } catch (Exception e) {
      log.error("Error serving ranged request for file", e);
      throw new RuntimeException("Error downloading file: " + e.getMessage(), e);
    }
  }

  @GetMapping("/{token}")
  public ResponseEntity<?> downloadFileByToken(
      @PathVariable String token,
      @RequestParam(value = "size", required = false) String size,
      WebRequest webRequest) {
    try {
      FileServeInfo fileInfo = fileStorageService.getFileServeInfoByPublicToken(token, size);

      // Caller asked for a derivative (thumb/medium/large) but processing hasn't produced it
      // yet. Returning the original here would either ship a HEIC the browser can't render or
      // waste bandwidth on the full-res image. Instead, return 202 Accepted with Retry-After
      // and let the client poll /api/assets/{id}/status.
      if (!fileInfo.isDerivativeReady()
          && fileInfo.getProcessingStatus() != ProcessingStatus.DONE) {
        return ResponseEntity.status(HttpStatus.ACCEPTED)
            .header(HttpHeaders.RETRY_AFTER, RETRY_AFTER_SECONDS)
            .cacheControl(CacheControl.noStore())
            .build();
      }

      // Answer conditional GETs *before* touching disk or MinIO. This is not just an
      // optimisation: Spring's HttpEntityMethodProcessor short-circuits an ETag match to 304
      // and returns without ever invoking the message converter, so a ResponseInputStream
      // opened here would never be closed and its pooled MinIO connection never returned. The
      // Apache pool is finite (see ObjectStorageConfig), so a browser reload — which
      // revalidates every cached thumbnail at once — used to bleed the pool dry and leave
      // subsequent image requests blocking in connection acquisition.
      if (isNotModified(webRequest, fileInfo)) {
        return null; // webRequest already set 304 + validators on the response
      }

      if (fileInfo.getStorageKey() != null) {
        return serveFromObjectStorage(fileInfo);
      }
      return serveFromDisk(token, fileInfo);
    } catch (RuntimeException e) {
      // See streamRangeByToken: 404 / 410 / 503 must reach the client with their own status.
      throw e;
    } catch (Exception e) {
      log.error("Error downloading file by token", e);
      throw new RuntimeException("Error downloading file: " + e.getMessage(), e);
    }
  }

  /**
   * Delegates If-None-Match / If-Modified-Since evaluation to Spring. Returns true when the
   * caller's cached copy is still valid, in which case the response has already been populated with
   * 304 and the validators. Returns false otherwise — but note that it stamps {@code ETag} and
   * {@code Last-Modified} onto the response either way, which is why the builders below no longer
   * set them (doing so would emit each header twice).
   */
  private boolean isNotModified(WebRequest webRequest, FileServeInfo fileInfo) {
    Instant uploadedAt = fileInfo.getUploadedAt();
    long lastModified = uploadedAt != null ? uploadedAt.toEpochMilli() : -1L;
    return webRequest.checkNotModified(fileInfo.getChecksum(), lastModified);
  }

  private ResponseEntity<Resource> serveFromDisk(String token, FileServeInfo fileInfo)
      throws Exception {
    Resource resource = new UrlResource(fileInfo.getFilePath().toUri());
    if (!resource.exists()) {
      // Derivative metadata exists but the file is missing on disk — fall back to the
      // original. This shouldn't normally happen but keeps the gallery functional if a
      // derivative is deleted out-of-band.
      fileInfo = fileStorageService.getFileServeInfoByPublicToken(token, "original");
      if (fileInfo.getStorageKey() != null) {
        return serveFromObjectStorage(fileInfo);
      }
      resource = new UrlResource(fileInfo.getFilePath().toUri());
      if (!resource.exists()) {
        throw new ResourceNotFoundException("File not found");
      }
    }

    MediaType mediaType = parseMediaType(fileInfo.getMimeType());
    return ResponseEntity.ok()
        .contentType(mediaType)
        .cacheControl(
            CacheControl.maxAge(365, java.util.concurrent.TimeUnit.DAYS).cachePublic().immutable())
        .header(
            HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + resource.getFilename() + "\"")
        .header(HttpHeaders.ACCEPT_RANGES, "bytes")
        .body(resource);
  }

  /**
   * The storage backend holding this asset. An S3 key is not self-describing — the same key can
   * exist in the instance's MinIO and in a user's own bucket — so the album decides the endpoint.
   */
  private BackendStorage storageFor(FileServeInfo fileInfo) {
    ObjectStorageService os =
        objectStorage.orElseThrow(
            () ->
                new IllegalStateException(
                    "Asset path is an S3 key but ObjectStorageService is not enabled — "
                        + "check storage.s3.enabled"));
    return os.forAlbumId(fileInfo.getAlbumId());
  }

  private ResponseEntity<Resource> serveFromObjectStorage(FileServeInfo fileInfo) {
    BackendStorage os = storageFor(fileInfo);

    ResponseInputStream<GetObjectResponse> stream = os.openStream(fileInfo.getStorageKey());
    GetObjectResponse meta = stream.response();
    Long contentLength = meta.contentLength();
    MediaType mediaType = parseMediaType(fileInfo.getMimeType());

    ResponseEntity.BodyBuilder builder =
        ResponseEntity.ok()
            .contentType(mediaType)
            .cacheControl(
                CacheControl.maxAge(365, java.util.concurrent.TimeUnit.DAYS)
                    .cachePublic()
                    .immutable())
            .header(
                HttpHeaders.CONTENT_DISPOSITION,
                "inline; filename=\"" + safeFilenameForKey(fileInfo) + "\"")
            .header(HttpHeaders.ACCEPT_RANGES, "bytes");
    if (contentLength != null) {
      builder.contentLength(contentLength);
    }
    return builder.body(new InputStreamResource(stream));
  }

  /**
   * Streams an S3-backed asset back with the caller's Range honoured. The header is forwarded to
   * MinIO so it does the slicing and the JVM only proxies bytes — the same shape {@code
   * SlideshowRecordingController} uses for audio. MinIO has no public ingress, so a redirect to a
   * presigned URL is not an option; the api pod must mediate.
   */
  private ResponseEntity<StreamingResponseBody> serveRangeFromObjectStorage(
      FileServeInfo fileInfo, String rangeHeader) {
    BackendStorage os = storageFor(fileInfo);

    ResponseInputStream<GetObjectResponse> stream =
        os.openStream(fileInfo.getStorageKey(), rangeHeader);
    GetObjectResponse meta = stream.response();
    boolean partial = meta.contentRange() != null;

    StreamingResponseBody body =
        (OutputStream out) -> {
          try (ResponseInputStream<GetObjectResponse> s = stream) {
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = s.read(buf)) > 0) {
              out.write(buf, 0, n);
            }
          }
        };

    ResponseEntity.BodyBuilder builder =
        ResponseEntity.status(partial ? HttpStatus.PARTIAL_CONTENT : HttpStatus.OK)
            .contentType(parseMediaType(fileInfo.getMimeType()))
            .cacheControl(
                CacheControl.maxAge(365, java.util.concurrent.TimeUnit.DAYS)
                    .cachePublic()
                    .immutable())
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .header(
                HttpHeaders.CONTENT_DISPOSITION,
                "inline; filename=\"" + safeFilenameForKey(fileInfo) + "\"");
    if (meta.contentLength() != null) {
      builder.contentLength(meta.contentLength());
    }
    if (partial) {
      builder.header(HttpHeaders.CONTENT_RANGE, meta.contentRange());
    }
    return builder.body(body);
  }

  private MediaType parseMediaType(String mime) {
    if (mime == null) {
      return MediaType.APPLICATION_OCTET_STREAM;
    }
    try {
      return MediaType.parseMediaType(mime);
    } catch (Exception ignored) {
      return MediaType.APPLICATION_OCTET_STREAM;
    }
  }

  private String safeFilenameForKey(FileServeInfo fileInfo) {
    // The Content-Disposition filename is for the user agent's "Save as..." dialog; the stored
    // filename is more meaningful here than the S3 key's basename (which for derivatives is
    // generic — thumb.jpg etc).
    String name = fileInfo.getFilename();
    return name != null ? name : "download";
  }
}
