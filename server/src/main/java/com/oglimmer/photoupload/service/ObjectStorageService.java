/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.StorageBackend;
import com.oglimmer.photoupload.exception.StorageException;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.storage.BackendStorage;
import com.oglimmer.photoupload.storage.StorageClientFactory;
import java.io.InputStream;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

/**
 * Entry point to object storage. Answers one question — <em>which</em> backend do these bytes live
 * in — and hands back a {@link BackendStorage} bound to it.
 *
 * <p>Storage is per album ({@code albums.storage_backend_id}), because a user may bring their own
 * S3 endpoint and pay for it themselves. Every asset belongs to exactly one album, so the backend
 * is always derivable from the row; nothing needs to be guessed and nothing needs a fallback.
 *
 * <p>Callers should route through {@link #forFile(FileMetadata)} or {@link #forAlbum(Album)}.
 * {@link #forSystemDefault()} is only for objects that belong to the instance rather than to an
 * album — in practice the {@code tus-uploads/} staging prefix, which tusd writes to before any
 * album is known.
 */
@Service
@ConditionalOnProperty(prefix = "storage.s3", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class ObjectStorageService {

  /**
   * How long an album→backend answer is reused. An album's backend never changes, so this cache
   * could live forever; the row's <em>credentials</em> can change, and the worker pod never sees
   * the api pod's edit, so the entry expires and is re-read. A minute is short enough that a
   * corrected access key takes effect without a restart and long enough that a gallery scroll does
   * not add one SELECT per thumbnail.
   */
  private static final Duration BACKEND_CACHE_TTL = Duration.ofSeconds(60);

  private final StorageClientFactory factory;
  private final StorageBackendRepository backendRepository;
  private final AlbumRepository albumRepository;

  private record CachedBackend(StorageBackend backend, long expiresAtMillis) {}

  private final Map<Long, CachedBackend> backendByAlbum = new ConcurrentHashMap<>();

  /**
   * Cached because it is read on every TUS upload and never changes: the system default row is
   * seeded by V44 and has no API that can edit or remove it.
   */
  private volatile StorageBackend cachedSystemBackend;

  public StorageBackend systemBackend() {
    StorageBackend cached = cachedSystemBackend;
    if (cached != null) {
      return cached;
    }
    StorageBackend found =
        backendRepository
            .findBySystemDefaultTrue()
            .orElseThrow(
                () ->
                    new StorageException(
                        "No system default storage backend row — V44 migration did not run"));
    cachedSystemBackend = found;
    return found;
  }

  public BackendStorage forBackend(StorageBackend backend) {
    return factory.storageFor(backend);
  }

  public BackendStorage forAlbum(Album album) {
    if (album == null) {
      throw new StorageException("Cannot resolve storage: no album");
    }
    return forAlbumId(album.getId());
  }

  public BackendStorage forAlbumId(Long albumId) {
    return forBackend(backendForAlbum(albumId));
  }

  public BackendStorage forFile(FileMetadata metadata) {
    if (metadata == null || metadata.getAlbum() == null) {
      throw new StorageException("Cannot resolve storage: file has no album");
    }
    // getId() on a lazy proxy reads the foreign key already in hand; it does not initialise the
    // album, so this is safe with open-in-view disabled.
    return forAlbumId(metadata.getAlbum().getId());
  }

  /** The backend row an album's bytes live in, memoised for {@link #BACKEND_CACHE_TTL}. */
  public StorageBackend backendForAlbum(Long albumId) {
    if (albumId == null) {
      throw new StorageException("Cannot resolve storage: no album id");
    }
    long now = System.currentTimeMillis();
    CachedBackend cached = backendByAlbum.get(albumId);
    if (cached != null && cached.expiresAtMillis() > now) {
      return cached.backend();
    }
    StorageBackend backend =
        albumRepository
            .findStorageBackendByAlbumId(albumId)
            .orElseThrow(
                () -> new StorageException("Album " + albumId + " has no storage backend row"));
    backendByAlbum.put(albumId, new CachedBackend(backend, now + BACKEND_CACHE_TTL.toMillis()));
    return backend;
  }

  /** Drops memoised rows for a backend the caller just changed, so this pod picks it up at once. */
  public void invalidateBackend(Long backendId) {
    backendByAlbum.values().removeIf(c -> backendId.equals(c.backend().getId()));
    factory.invalidate(backendId);
  }

  /** The operator's own MinIO — the {@code storage.s3.*} endpoint. */
  public BackendStorage forSystemDefault() {
    return forBackend(systemBackend());
  }

  /**
   * Move an object from one backend to another, or within one.
   *
   * <p>Same backend is a server-side COPY: no bytes touch the JVM. Different backends have no such
   * shortcut — S3 cannot copy across endpoints — so the object is streamed through this pod,
   * download and upload at once. That is the cost of an album on a user's own storage, and it is
   * why the TUS staging area stays on the system default: it keeps the expensive path to exactly
   * one hop per upload instead of two.
   *
   * <p>The source object is left in place; the caller deletes it once the destination is durable.
   */
  public void transfer(
      BackendStorage source,
      String sourceKey,
      BackendStorage destination,
      String destinationKey,
      String contentType) {
    if (source.getBackendId() != null && source.getBackendId().equals(destination.getBackendId())) {
      source.copy(sourceKey, destinationKey, contentType);
      return;
    }
    try (ResponseInputStream<GetObjectResponse> in = source.openStream(sourceKey)) {
      long length = in.response().contentLength();
      String effectiveType =
          contentType != null && !contentType.isBlank() ? contentType : in.response().contentType();
      destination.putStream(destinationKey, in, length, effectiveType);
      log.info(
          "Cross-backend transfer {} bytes: backend {} {} → backend {} {}",
          length,
          source.getBackendId(),
          sourceKey,
          destination.getBackendId(),
          destinationKey);
    } catch (StorageException e) {
      throw e;
    } catch (java.io.IOException e) {
      throw new StorageException(
          "Failed to transfer " + sourceKey + " between storage backends: " + e.getMessage(), e);
    }
  }

  /** Overload for callers that already hold the stream (used by tests and probe paths). */
  public void transfer(
      InputStream in, long length, BackendStorage destination, String key, String contentType) {
    destination.putStream(key, in, length, contentType);
  }
}
