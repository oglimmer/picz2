/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.tus.TusHookRequest;
import com.oglimmer.photoupload.model.tus.TusHookResponse;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.UserRepository;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.AuthenticationException;
import org.springframework.stereotype.Service;

/**
 * Phase 5 — pre-create / post-finish / post-terminate handlers for tusd hooks.
 *
 * <p>Decisions enforced here:
 *
 * <ul>
 *   <li><b>D26</b> — auth comes from {@code Upload-Metadata.auth} as plaintext {@code
 *       email:password} and is validated through the existing {@link AuthenticationManager}.
 *   <li><b>D28</b> — pre-create rejects 503 with {@code Retry-After} when the {@code
 *       processing_jobs} backlog is above the configured threshold; tusd never starts buffering
 *       bytes for a doomed upload.
 *   <li><b>D30</b> — pre-create rejects 409 when the supplied {@code contentId} already maps to
 *       a row for the same user.
 * </ul>
 *
 * <p>Every method returns a {@link TusHookResponse}. The controller wraps this in HTTP 200 + JSON
 * body — tusd JSON-decodes the body, and {@code HTTPResponse.StatusCode} inside it is what tusd
 * surfaces to the actual client. Returning a non-2xx HTTP status or an empty body would make
 * tusd log "failed to parse hook response" and propagate 500 to the client — that was the R1
 * deploy bug.
 *
 * <p>post-finish is intentionally written to never reject: any error after tusd itself succeeded
 * leaves at most an orphan {@code originals/...} object that the operator orphan-detection
 * follow-up sweeps. Rejecting would loop tusd retries against an already-finalised upload.
 */
@Profile(Profiles.API)
@Service
@ConditionalOnProperty(prefix = "tus", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class TusHookService {

  /** S3 prefix tusd writes uploads under (must match the {@code -s3-object-prefix} flag). */
  private static final String TUS_UPLOADS_PREFIX = "tus-uploads/";

  /** Metadata key carrying the iOS / web bearer credentials. */
  private static final String META_AUTH = "auth";

  /** Metadata key carrying the source-asset stable id (sha256 from client). */
  private static final String META_CONTENT_ID = "contentId";

  /** Metadata key carrying the destination album id. */
  private static final String META_ALBUM_ID = "albumId";

  /** Metadata key carrying the original filename. tusd's {@code filename} convention. */
  private static final String META_FILENAME = "filename";

  /** Metadata key carrying the mime type. tusd's {@code filetype} convention. */
  private static final String META_FILETYPE = "filetype";

  private final FileStorageService fileStorageService;
  private final FileMetadataRepository metadataRepository;
  private final UserRepository userRepository;
  private final AuthenticationManager authenticationManager;
  private final JobsProperties jobsProperties;
  private final JobQueueDepthService queueDepthService;

  public TusHookResponse handlePreCreate(TusHookRequest request) {
    Map<String, String> meta = metadataOf(request);

    User user;
    try {
      user = authenticate(meta.get(META_AUTH));
    } catch (AuthenticationException e) {
      log.warn("TUS pre-create rejected: invalid auth ({})", e.getMessage());
      return TusHookResponse.reject(401, "unauthorized");
    }

    int threshold = jobsProperties.getBackpressure().getQueueDepthThreshold();
    long depth = queueDepthService.getDepth();
    if (depth > threshold) {
      log.info(
          "TUS pre-create rejected: queue depth {} > threshold {} (user {})",
          depth,
          threshold,
          user.getId());
      return TusHookResponse.reject(503, "backpressure", Map.of("Retry-After", "30"));
    }

    String contentId = meta.get(META_CONTENT_ID);
    if (contentId != null && !contentId.isBlank()) {
      List<FileMetadata> existing =
          metadataRepository.findByContentIdAndUserId(contentId, user.getId());
      if (!existing.isEmpty()) {
        log.info(
            "TUS pre-create rejected: duplicate contentId {} for user {} (existing asset {})",
            contentId,
            user.getId(),
            existing.get(0).getId());
        return TusHookResponse.reject(409, "duplicate-content-id");
      }
    }

    return TusHookResponse.allow();
  }

  public TusHookResponse handlePostFinish(TusHookRequest request) {
    TusHookRequest.TusUpload upload = uploadOf(request);
    Map<String, String> meta = metadataOf(request);
    // tusd S3 store uses Upload.ID = "<objectName>+<multipartUploadId>"; the actual S3 key is
    // the part before the '+'. Prefer the authoritative Storage.Key from the hook payload;
    // fall back to splitting the id ourselves only if a future tusd version drops Storage.
    String tusKey = resolveTusKey(upload);

    User user;
    try {
      user = authenticate(meta.get(META_AUTH));
    } catch (AuthenticationException e) {
      log.error(
          "TUS post-finish auth failed for upload {} (key={}); orphan cleanup may be needed",
          upload.id(),
          tusKey,
          e);
      return TusHookResponse.allow();
    }

    String contentId = meta.get(META_CONTENT_ID);
    if (contentId != null && !contentId.isBlank()) {
      List<FileMetadata> existing =
          metadataRepository.findByContentIdAndUserId(contentId, user.getId());
      if (!existing.isEmpty()) {
        log.info(
            "TUS post-finish: idempotent retry for contentId {} (asset {} already registered)",
            contentId,
            existing.get(0).getId());
        return TusHookResponse.allow();
      }
    }

    Long albumId = parseLong(meta.get(META_ALBUM_ID));
    String filename = orDefault(meta.get(META_FILENAME), upload.id());
    String contentType = orDefault(meta.get(META_FILETYPE), "application/octet-stream");

    try {
      FileInfo info =
          fileStorageService.registerTusUpload(
              user, albumId, tusKey, filename, upload.size(), contentType, contentId);
      log.info(
          "TUS post-finish: registered asset {} for user {} from {}",
          info.getId(),
          user.getId(),
          tusKey);
    } catch (RuntimeException e) {
      log.error(
          "TUS post-finish: register failed for upload {} (key={}); orphan cleanup may be needed",
          upload.id(),
          tusKey,
          e);
    }
    return TusHookResponse.allow();
  }

  public TusHookResponse handlePostTerminate(TusHookRequest request) {
    TusHookRequest.TusUpload upload = uploadOf(request);
    log.info(
        "TUS upload {} terminated by client; tusd has cleaned up {}",
        upload.id(),
        resolveTusKey(upload));
    return TusHookResponse.allow();
  }

  /**
   * Returns the S3 object key tusd actually wrote to. Prefers {@code Storage.Key} from the hook
   * payload — that's tusd's source of truth and is unaffected by the {@code <objectName>+
   * <multipartUploadId>} format of {@code Upload.ID}. Falls back to the splitting heuristic
   * only if {@code Storage} is missing (older tusd, or a hook event we don't fully understand).
   */
  private static String resolveTusKey(TusHookRequest.TusUpload upload) {
    if (upload.storage() != null) {
      String key = upload.storage().get("Key");
      if (key != null && !key.isBlank()) {
        return key;
      }
    }
    String id = upload.id();
    if (id == null) {
      throw new IllegalArgumentException("TUS upload missing both Storage.Key and ID");
    }
    int plus = id.indexOf('+');
    String objectName = plus < 0 ? id : id.substring(0, plus);
    return TUS_UPLOADS_PREFIX + objectName;
  }

  private TusHookRequest.TusUpload uploadOf(TusHookRequest request) {
    if (request == null || request.event() == null || request.event().upload() == null) {
      throw new IllegalArgumentException("TUS hook payload missing Event.Upload");
    }
    return request.event().upload();
  }

  private Map<String, String> metadataOf(TusHookRequest request) {
    TusHookRequest.TusUpload upload = uploadOf(request);
    return upload.metaData() == null ? Map.of() : upload.metaData();
  }

  private User authenticate(String authValue) {
    if (authValue == null || authValue.isBlank()) {
      throw new BadCredentialsException("missing auth metadata");
    }
    int colon = authValue.indexOf(':');
    if (colon < 0) {
      throw new BadCredentialsException("malformed auth metadata");
    }
    String username = authValue.substring(0, colon);
    String password = authValue.substring(colon + 1);
    authenticationManager.authenticate(
        new UsernamePasswordAuthenticationToken(username, password));
    return userRepository
        .findByEmail(username)
        .orElseThrow(() -> new BadCredentialsException("user not found: " + username));
  }

  private static Long parseLong(String s) {
    if (s == null || s.isBlank()) {
      return null;
    }
    try {
      return Long.parseLong(s);
    } catch (NumberFormatException e) {
      return null;
    }
  }

  private static String orDefault(String s, String fallback) {
    return (s == null || s.isBlank()) ? fallback : s;
  }
}
