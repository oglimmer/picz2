/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.model.tus.TusHookRequest;
import com.oglimmer.photoupload.model.tus.TusHookResponse;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.UserRepository;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;

@ExtendWith(MockitoExtension.class)
class TusHookServiceTest {

  @Mock FileStorageService fileStorageService;
  @Mock FileMetadataRepository metadataRepository;
  @Mock UserRepository userRepository;
  @Mock AuthenticationManager authenticationManager;
  @Mock JobsProperties jobsProperties;
  @Mock JobsProperties.Backpressure backpressure;
  @Mock JobQueueDepthService queueDepthService;

  /**
   * Quota check on pre-create. A permissive mock by default: these tests are about auth,
   * backpressure and duplicate detection, and the quota has its own coverage.
   */
  @Mock StorageQuotaService storageQuotaService;

  /**
   * The real properties object, not a mock: {@code duplicateDetectionEnabled} defaults to true and
   * that default is what production runs, so every test here exercises the dedupe path unless it
   * says otherwise.
   */
  @Spy FileStorageProperties fileStorageProperties = new FileStorageProperties();

  @InjectMocks TusHookService service;

  private User testUser;

  @BeforeEach
  void setUp() {
    testUser = new User();
    testUser.setId(42L);
    testUser.setEmail("alice@example.com");
  }

  // -- pre-create -----------------------------------------------------------------------------

  @Test
  void preCreateRejectsMissingAuth() {
    TusHookResponse resp = service.handlePreCreate(preCreate(meta(Map.of("filename", "x.jpg"))));
    assertTrue(resp.rejectUpload());
    assertEquals(401, resp.httpResponse().statusCode());
    verifyNoInteractions(authenticationManager);
  }

  @Test
  void preCreateRejectsBadCredentials() {
    when(authenticationManager.authenticate(any())).thenThrow(new BadCredentialsException("nope"));

    TusHookResponse resp =
        service.handlePreCreate(preCreate(meta(Map.of("auth", "alice@example.com:wrong"))));

    assertTrue(resp.rejectUpload());
    assertEquals(401, resp.httpResponse().statusCode());
    verify(metadataRepository, never()).findByContentIdAndUserId(anyString(), anyLong());
  }

  @Test
  void preCreateRejectsBackpressure() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(jobsProperties.getBackpressure()).thenReturn(backpressure);
    when(backpressure.getQueueDepthThreshold()).thenReturn(200);
    when(queueDepthService.getDepth()).thenReturn(250L);

    TusHookResponse resp =
        service.handlePreCreate(preCreate(meta(Map.of("auth", "alice@example.com:pw"))));

    assertTrue(resp.rejectUpload());
    assertEquals(503, resp.httpResponse().statusCode());
    assertEquals("30", resp.httpResponse().header().get("Retry-After"));
    verify(metadataRepository, never()).findByContentIdAndUserId(anyString(), anyLong());
  }

  @Test
  void preCreateRejectsDuplicateContentId() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(jobsProperties.getBackpressure()).thenReturn(backpressure);
    when(backpressure.getQueueDepthThreshold()).thenReturn(200);
    when(queueDepthService.getDepth()).thenReturn(0L);

    FileMetadata existing = new FileMetadata();
    existing.setId(99L);
    when(metadataRepository.findByContentIdAndUserId("sha-deadbeef", 42L))
        .thenReturn(List.of(existing));

    TusHookResponse resp =
        service.handlePreCreate(
            preCreate(meta(Map.of("auth", "alice@example.com:pw", "contentId", "sha-deadbeef"))));

    assertTrue(resp.rejectUpload());
    assertEquals(409, resp.httpResponse().statusCode());
    assertNotNull(resp.httpResponse().body());
  }

  /**
   * The iPhone-and-iPad case (D61). Each device gives the same iCloud photo its own {@code
   * PHAsset.localIdentifier}, so the contentId lookup finds nothing — the SHA-256 over the
   * untouched original resource is the only thing that matches, and it must be enough.
   */
  @Test
  void preCreateRejectsDuplicateChecksumFromAnotherDevice() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(jobsProperties.getBackpressure()).thenReturn(backpressure);
    when(backpressure.getQueueDepthThreshold()).thenReturn(200);
    when(queueDepthService.getDepth()).thenReturn(0L);

    // The iPad's own local identifier: unknown to the server, and that is the point.
    when(metadataRepository.findByContentIdAndUserId("ipad-local-id", 42L)).thenReturn(List.of());

    FileMetadata existing = new FileMetadata();
    existing.setId(99L);
    when(metadataRepository.findByChecksumAndUserId("sha-deadbeef", 42L))
        .thenReturn(List.of(existing));

    TusHookResponse resp =
        service.handlePreCreate(
            preCreate(
                meta(
                    Map.of(
                        "auth", "alice@example.com:pw",
                        "contentId", "ipad-local-id",
                        "checksum", "sha-deadbeef"))));

    assertTrue(resp.rejectUpload());
    assertEquals(409, resp.httpResponse().statusCode());
  }

  /** A checksum the account has never seen must not be mistaken for a duplicate. */
  @Test
  void preCreateAllowsUnknownChecksum() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(jobsProperties.getBackpressure()).thenReturn(backpressure);
    when(backpressure.getQueueDepthThreshold()).thenReturn(200);
    when(queueDepthService.getDepth()).thenReturn(0L);
    when(metadataRepository.findByContentIdAndUserId("fresh", 42L)).thenReturn(List.of());
    when(metadataRepository.findByChecksumAndUserId("sha-new", 42L)).thenReturn(List.of());

    TusHookResponse resp =
        service.handlePreCreate(
            preCreate(
                meta(
                    Map.of(
                        "auth", "alice@example.com:pw",
                        "contentId", "fresh",
                        "checksum", "sha-new"))));

    assertFalse(resp.rejectUpload());
  }

  /**
   * An older build sends no checksum at all. It has to keep uploading — a blank value is "unknown",
   * never "matches everything" — and the repository must not be asked.
   */
  @Test
  void preCreateSkipsChecksumGateWhenClientSendsNone() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(jobsProperties.getBackpressure()).thenReturn(backpressure);
    when(backpressure.getQueueDepthThreshold()).thenReturn(200);
    when(queueDepthService.getDepth()).thenReturn(0L);
    when(metadataRepository.findByContentIdAndUserId("fresh", 42L)).thenReturn(List.of());

    TusHookResponse resp =
        service.handlePreCreate(
            preCreate(meta(Map.of("auth", "alice@example.com:pw", "contentId", "fresh"))));

    assertFalse(resp.rejectUpload());
    verify(metadataRepository, never()).findByChecksumAndUserId(anyString(), anyLong());
  }

  @Test
  void preCreateAllowsHappyPath() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(jobsProperties.getBackpressure()).thenReturn(backpressure);
    when(backpressure.getQueueDepthThreshold()).thenReturn(200);
    when(queueDepthService.getDepth()).thenReturn(5L);
    when(metadataRepository.findByContentIdAndUserId("fresh", 42L)).thenReturn(List.of());

    TusHookResponse resp =
        service.handlePreCreate(
            preCreate(meta(Map.of("auth", "alice@example.com:pw", "contentId", "fresh"))));

    assertFalse(resp.rejectUpload());
    // allow() passes null HTTPResponse so tusd uses its default 200/201.
    assertEquals(null, resp.httpResponse());
  }

  // -- post-finish ----------------------------------------------------------------------------

  @Test
  void postFinishRegistersUpload() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(metadataRepository.findByContentIdAndUserId("fresh", 42L)).thenReturn(List.of());
    when(metadataRepository.findByChecksumAndUserId("sha-abc", 42L)).thenReturn(List.of());

    FileInfo result = new FileInfo();
    result.setId(1234L);
    when(fileStorageService.registerTusUpload(
            eq(testUser),
            eq(7L),
            eq("tus-uploads/abc123"),
            eq("photo.jpg"),
            eq(2048L),
            eq("image/jpeg"),
            eq("fresh"),
            eq("sha-abc")))
        .thenReturn(result);

    TusHookResponse resp =
        service.handlePostFinish(
            postFinish(
                "abc123",
                2048L,
                Map.of(
                    "auth", "alice@example.com:pw",
                    "contentId", "fresh",
                    "checksum", "sha-abc",
                    "albumId", "7",
                    "filename", "photo.jpg",
                    "filetype", "image/jpeg")));

    assertFalse(resp.rejectUpload());
    verify(fileStorageService, times(1))
        .registerTusUpload(
            any(),
            anyLong(),
            anyString(),
            anyString(),
            anyLong(),
            anyString(),
            anyString(),
            anyString());
  }

  @Test
  void postFinishIdempotentOnDuplicateContentId() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));

    FileMetadata existing = new FileMetadata();
    existing.setId(55L);
    when(metadataRepository.findByContentIdAndUserId("fresh", 42L)).thenReturn(List.of(existing));

    TusHookResponse resp =
        service.handlePostFinish(
            postFinish(
                "abc123",
                2048L,
                Map.of(
                    "auth", "alice@example.com:pw",
                    "contentId", "fresh",
                    "checksum", "sha-abc",
                    "albumId", "7",
                    "filename", "photo.jpg",
                    "filetype", "image/jpeg")));

    assertFalse(resp.rejectUpload());
    verifyNoInteractions(fileStorageService);
  }

  /**
   * Two devices can clear pre-create in the same instant and both upload. The loser of that race
   * must not get a row — post-finish re-checks after the bytes have landed. The stranded
   * tus-uploads/ object is left to the nightly retention sweep, exactly as the duplicate-contentId
   * branch already does.
   */
  @Test
  void postFinishDropsDuplicateChecksum() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(metadataRepository.findByContentIdAndUserId("ipad-local-id", 42L)).thenReturn(List.of());

    FileMetadata existing = new FileMetadata();
    existing.setId(77L);
    when(metadataRepository.findByChecksumAndUserId("sha-abc", 42L)).thenReturn(List.of(existing));

    TusHookResponse resp =
        service.handlePostFinish(
            postFinish(
                "abc123",
                2048L,
                Map.of(
                    "auth", "alice@example.com:pw",
                    "contentId", "ipad-local-id",
                    "checksum", "sha-abc",
                    "albumId", "7",
                    "filename", "photo.jpg",
                    "filetype", "image/jpeg")));

    assertFalse(resp.rejectUpload());
    verifyNoInteractions(fileStorageService);
  }

  @Test
  void postFinishSwallowsAuthFailure() {
    when(authenticationManager.authenticate(any())).thenThrow(new BadCredentialsException("nope"));

    TusHookResponse resp =
        service.handlePostFinish(
            postFinish("abc123", 2048L, Map.of("auth", "alice@example.com:wrong")));

    // Returning allow() keeps tusd from looping retries against an upload it already finalised.
    // Operator orphan-cleanup picks up any stranded tus-uploads/* objects.
    assertFalse(resp.rejectUpload());
    verifyNoInteractions(fileStorageService);
  }

  @Test
  void postFinishSwallowsRegisterFailure() {
    when(authenticationManager.authenticate(any()))
        .thenReturn(new UsernamePasswordAuthenticationToken("alice@example.com", "pw"));
    when(userRepository.findByEmail("alice@example.com")).thenReturn(Optional.of(testUser));
    when(metadataRepository.findByContentIdAndUserId("fresh", 42L)).thenReturn(List.of());
    when(metadataRepository.findByChecksumAndUserId("sha-abc", 42L)).thenReturn(List.of());
    when(fileStorageService.registerTusUpload(
            any(),
            anyLong(),
            anyString(),
            anyString(),
            anyLong(),
            anyString(),
            anyString(),
            anyString()))
        .thenThrow(new IllegalStateException("S3 dead"));

    TusHookResponse resp =
        service.handlePostFinish(
            postFinish(
                "abc123",
                2048L,
                Map.of(
                    "auth", "alice@example.com:pw",
                    "contentId", "fresh",
                    "checksum", "sha-abc",
                    "albumId", "7",
                    "filename", "photo.jpg",
                    "filetype", "image/jpeg")));

    assertFalse(resp.rejectUpload());
  }

  // -- post-terminate -------------------------------------------------------------------------

  @Test
  void postTerminateAcks() {
    TusHookRequest req =
        new TusHookRequest(
            "post-terminate",
            new TusHookRequest.TusEvent(
                new TusHookRequest.TusUpload("abc123", 0L, 0L, Map.of(), null), null));
    TusHookResponse resp = service.handlePostTerminate(req);
    assertFalse(resp.rejectUpload());
  }

  // -- helpers --------------------------------------------------------------------------------

  private static TusHookRequest preCreate(Map<String, String> metaData) {
    return new TusHookRequest(
        "pre-create",
        new TusHookRequest.TusEvent(
            new TusHookRequest.TusUpload(null, 0L, 0L, metaData, null), null));
  }

  private static TusHookRequest postFinish(String id, long size, Map<String, String> metaData) {
    // Storage carries the authoritative S3 key — synthesise it the same way tusd does so the
    // service's resolveTusKey() picks up the right value (the tests don't go through the real
    // tusd, so we hand-build the FileInfo.Storage shape here).
    return new TusHookRequest(
        "post-finish",
        new TusHookRequest.TusEvent(
            new TusHookRequest.TusUpload(
                id,
                size,
                size,
                metaData,
                Map.of("Type", "s3store", "Bucket", "photo-upload", "Key", "tus-uploads/" + id)),
            null));
  }

  private static Map<String, String> meta(Map<String, String> kv) {
    return new HashMap<>(kv);
  }
}
