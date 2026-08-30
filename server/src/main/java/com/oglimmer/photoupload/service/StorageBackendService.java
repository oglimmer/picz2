/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.model.StorageBackendRequest;
import com.oglimmer.photoupload.model.StorageBackendResponse;
import com.oglimmer.photoupload.model.StorageBackendTestResult;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.security.SecretCipher;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.storage.BackendStorage;
import com.oglimmer.photoupload.storage.StorageClientFactory;
import com.oglimmer.photoupload.storage.StorageClients;
import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * CRUD for user-owned S3 endpoints — "bring your own storage". The metadata database stays with the
 * instance; the bytes, and the bill for them, can be the user's.
 *
 * <p>Every write path proves the endpoint works before it is saved. A backend that only fails at
 * upload time would strand photos the user believes are safe, so the probe does a real
 * write-read-delete round trip rather than a HEAD, and a failure is reported as a validation error
 * on the form instead of an outage later.
 */
@Service
@Profile(Profiles.API)
@RequiredArgsConstructor
@Slf4j
public class StorageBackendService {

  /** Key used by the connection probe. Ends up deleted; harmless if a delete ever fails. */
  private static final String PROBE_PREFIX = ".zyncloud-connection-test/";

  private final StorageBackendRepository repository;
  private final UserContext userContext;
  private final SecretCipher secretCipher;
  private final StorageQuotaService storageQuotaService;
  private final Optional<StorageClientFactory> clientFactory;
  private final Optional<ObjectStorageService> objectStorage;

  /** Backends this user may pick when creating an album: the system default plus their own. */
  @Transactional(readOnly = true)
  public List<StorageBackendResponse> listSelectable() {
    User user = userContext.getCurrentUser();
    return repository.findSelectableForUser(user.getId()).stream().map(this::toResponse).toList();
  }

  @Transactional(readOnly = true)
  public StorageBackendResponse get(Long id) {
    return toResponse(requireOwned(id));
  }

  @Transactional
  public StorageBackendResponse create(StorageBackendRequest request) {
    User user = userContext.getCurrentUser();
    validateRequest(request, true);

    if (repository.existsByUserIdAndName(user.getId(), request.getName())) {
      throw new DuplicateResourceException("StorageBackend", "name", request.getName());
    }

    StorageBackend backend = new StorageBackend();
    backend.setUser(user);
    backend.setSystemDefault(false);
    applyRequest(backend, request);

    requireWorkingConnection(backend);

    StorageBackend saved = repository.save(backend);
    log.info(
        "User {} registered storage backend {} ({} bucket {})",
        user.getEmail(),
        saved.getId(),
        saved.getEndpoint(),
        saved.getBucket());
    return toResponse(saved);
  }

  @Transactional
  public StorageBackendResponse update(Long id, StorageBackendRequest request) {
    StorageBackend backend = requireOwned(id);
    validateRequest(request, false);

    if (!backend.getName().equals(request.getName())
        && repository.existsByUserIdAndName(backend.getUser().getId(), request.getName())) {
      throw new DuplicateResourceException("StorageBackend", "name", request.getName());
    }

    applyRequest(backend, request);
    requireWorkingConnection(backend);

    StorageBackend saved = repository.save(backend);
    // This pod can drop its cached client immediately; the worker and retention pods notice on
    // their own within the router's cache TTL. Nothing here needs a restart.
    objectStorage.ifPresent(os -> os.invalidateBackend(saved.getId()));
    log.info("Storage backend {} updated", saved.getId());
    return toResponse(saved);
  }

  @Transactional
  public void delete(Long id) {
    StorageBackend backend = requireOwned(id);
    long albums = repository.countAlbumsUsing(id);
    if (albums > 0) {
      // Deleting would leave those albums pointing at nothing, and their bytes unreachable. The
      // user has to move or delete the albums first — a decision only they can make.
      throw new ValidationException(
          "This storage is still used by "
              + albums
              + (albums == 1 ? " album" : " albums")
              + ". Delete or move those albums first.");
    }
    repository.delete(backend);
    objectStorage.ifPresent(os -> os.invalidateBackend(id));
    log.info("Storage backend {} deleted", id);
  }

  /**
   * Try the settings without saving anything. The form calls this so a user can iterate on a
   * mistyped endpoint without creating half-working rows.
   *
   * <p>On an existing backend an omitted {@code secretKey} means "use the stored one", so the check
   * can be repeated later without re-typing the secret.
   */
  @Transactional(readOnly = true)
  public StorageBackendTestResult test(Long existingId, StorageBackendRequest request) {
    StorageClientFactory factory =
        clientFactory.orElseThrow(
            () -> new ValidationException("Object storage is disabled on this server"));

    String secret = request.getSecretKey();
    if ((secret == null || secret.isBlank()) && existingId != null) {
      secret = secretCipher.decrypt(requireOwned(existingId).getSecretKeyEncrypted());
    }
    if (secret == null || secret.isBlank()) {
      return new StorageBackendTestResult(false, "connect", "Secret key is required");
    }

    StorageClientFactory.Settings settings =
        new StorageClientFactory.Settings(
            normaliseEndpoint(request.getEndpoint()),
            blankToDefault(request.getRegion(), "us-east-1"),
            request.getBucket(),
            request.getAccessKey(),
            secret,
            request.getPathStyleAccess() == null || request.getPathStyleAccess());

    return probe(factory, settings);
  }

  // ---------------------------------------------------------------- internals

  private StorageBackend requireOwned(Long id) {
    User user = userContext.getCurrentUser();
    return repository
        .findByIdAndUserId(id, user.getId())
        .orElseThrow(() -> new ResourceNotFoundException("StorageBackend", "id", id));
  }

  private void validateRequest(StorageBackendRequest request, boolean creating) {
    if (isBlank(request.getName())) {
      throw new ValidationException("Name is required");
    }
    if (isBlank(request.getEndpoint())) {
      throw new ValidationException("Endpoint is required");
    }
    String endpoint = normaliseEndpoint(request.getEndpoint());
    URI uri;
    try {
      uri = URI.create(endpoint);
    } catch (IllegalArgumentException e) {
      throw new ValidationException("Endpoint is not a valid URL");
    }
    if (uri.getScheme() == null
        || !(uri.getScheme().equals("http") || uri.getScheme().equals("https"))
        || uri.getHost() == null) {
      throw new ValidationException("Endpoint must be a http:// or https:// URL with a host");
    }
    if (isBlank(request.getBucket())) {
      throw new ValidationException("Bucket is required");
    }
    if (isBlank(request.getAccessKey())) {
      throw new ValidationException("Access key is required");
    }
    if (creating && isBlank(request.getSecretKey())) {
      throw new ValidationException("Secret key is required");
    }
    if (!secretCipher.isEnabled()) {
      throw new ValidationException(
          "This server cannot store storage credentials — the operator must set"
              + " storage.backend-secret-key.");
    }
  }

  private void applyRequest(StorageBackend backend, StorageBackendRequest request) {
    backend.setName(request.getName().trim());
    backend.setEndpoint(normaliseEndpoint(request.getEndpoint()));
    backend.setRegion(blankToDefault(request.getRegion(), "us-east-1"));
    backend.setBucket(request.getBucket().trim());
    backend.setAccessKey(request.getAccessKey().trim());
    backend.setPathStyleAccess(
        request.getPathStyleAccess() == null || request.getPathStyleAccess());
    // An absent secret on an update means "unchanged"; only a supplied one is re-encrypted.
    if (!isBlank(request.getSecretKey())) {
      backend.setSecretKeyEncrypted(secretCipher.encrypt(request.getSecretKey().trim()));
    }
    if (backend.getSecretKeyEncrypted() == null) {
      throw new ValidationException("Secret key is required");
    }
  }

  private void requireWorkingConnection(StorageBackend backend) {
    StorageClientFactory factory =
        clientFactory.orElseThrow(
            () -> new ValidationException("Object storage is disabled on this server"));
    StorageBackendTestResult result = probe(factory, factory.settingsOf(backend));
    if (!result.isOk()) {
      throw new ValidationException(
          "Could not use this storage (" + result.getFailedStep() + "): " + result.getMessage());
    }
  }

  /**
   * Real round trip: PUT a few bytes, GET them back, DELETE them. A HEAD on the bucket is not
   * enough — read-only credentials pass it and then lose every upload.
   */
  private StorageBackendTestResult probe(
      StorageClientFactory factory, StorageClientFactory.Settings settings) {
    StorageClients clients = null;
    String key = PROBE_PREFIX + UUID.randomUUID();
    Path scratch = null;
    try {
      clients = factory.probeClients(settings);
      BackendStorage storage = factory.storageFor(clients);

      byte[] payload =
          ("zyncloud connection test " + java.time.Instant.now()).getBytes(StandardCharsets.UTF_8);
      scratch = Files.createTempFile("zyncloud-probe", ".txt");
      Files.write(scratch, payload);

      try {
        storage.putFile(key, scratch, "text/plain");
      } catch (Exception e) {
        return new StorageBackendTestResult(false, "write", rootMessage(e));
      }

      try {
        if (!storage.exists(key)) {
          return new StorageBackendTestResult(
              false, "read", "The object was written but could not be read back");
        }
      } catch (Exception e) {
        return new StorageBackendTestResult(false, "read", rootMessage(e));
      }

      try {
        storage.delete(key);
      } catch (Exception e) {
        return new StorageBackendTestResult(false, "delete", rootMessage(e));
      }

      return new StorageBackendTestResult(true, null, null);
    } catch (IOException e) {
      return new StorageBackendTestResult(false, "connect", rootMessage(e));
    } catch (Exception e) {
      return new StorageBackendTestResult(false, "connect", rootMessage(e));
    } finally {
      if (scratch != null) {
        try {
          Files.deleteIfExists(scratch);
        } catch (IOException ignored) {
          // Temp file in the OS temp dir; the OS reaps it.
        }
      }
      if (clients != null) {
        factory.close(clients);
      }
    }
  }

  /**
   * The innermost message, which is the one that names the actual problem ("The specified bucket
   * does not exist", "Connection refused"). The SDK's outer wrapper says only that a call failed.
   */
  private String rootMessage(Throwable e) {
    Throwable cause = e;
    while (cause.getCause() != null && cause.getCause() != cause) {
      cause = cause.getCause();
    }
    String message = cause.getMessage();
    return message == null || message.isBlank() ? cause.getClass().getSimpleName() : message;
  }

  private StorageBackendResponse toResponse(StorageBackend backend) {
    // Usage is only meaningful for the instance's own storage; a user's own bucket is theirs to
    // fill, and we could not measure it without listing it on every request anyway.
    StorageQuotaService.Usage usage =
        backend.isSystemDefault()
            ? storageQuotaService.usageFor(userContext.getCurrentUser())
            : null;
    return new StorageBackendResponse(
        backend.getId(),
        backend.getName(),
        backend.isSystemDefault(),
        backend.getEndpoint(),
        backend.getRegion(),
        backend.getBucket(),
        backend.getAccessKey(),
        backend.isPathStyleAccess(),
        repository.countAlbumsUsing(backend.getId()),
        backend.getCreatedAt(),
        usage != null ? usage.usedBytes() : null,
        usage != null ? usage.quotaBytes() : null);
  }

  private static String normaliseEndpoint(String endpoint) {
    if (endpoint == null) {
      return null;
    }
    String trimmed = endpoint.trim();
    // A trailing slash makes the SDK build keys with a double slash, which some gateways treat as
    // a different object than the one we later ask for.
    while (trimmed.endsWith("/")) {
      trimmed = trimmed.substring(0, trimmed.length() - 1);
    }
    return trimmed;
  }

  private static String blankToDefault(String value, String fallback) {
    return isBlank(value) ? fallback : value.trim();
  }

  private static boolean isBlank(String value) {
    return value == null || value.isBlank();
  }
}
