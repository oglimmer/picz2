/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.config.JobsProperties;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/** The per-asset caption written by the album owner and read by public visitors (D69). */
class FileStorageServiceCaptionTest {

  private static final long FILE_ID = 100L;

  private FileMetadataRepository metaRepo;
  private ImageTagRepository imageTagRepo;
  private FileStorageService svc;

  private User user;
  private FileMetadata file;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = Mockito.mock(FileMetadataRepository.class);
    imageTagRepo = Mockito.mock(ImageTagRepository.class);
    UserContext userContext = Mockito.mock(UserContext.class);
    FileInfoMapper mapper = Mockito.mock(FileInfoMapper.class);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            Mockito.mock(TagRepository.class),
            imageTagRepo,
            Mockito.mock(AlbumEnabledTagRepository.class),
            Mockito.mock(JdbcTemplate.class),
            Mockito.mock(AlbumRepository.class),
            Mockito.mock(SlideshowRecordingRepository.class),
            Mockito.mock(StorageBackendRepository.class),
            mapper,
            userContext,
            Mockito.mock(PlatformTransactionManager.class),
            Mockito.mock(JobEnqueueService.class),
            Mockito.mock(SystemTagProvisioner.class),
            Mockito.mock(StorageQuotaService.class),
            Mockito.mock(ObjectStorageService.class),
            Mockito.mock(JobQueueDepthService.class),
            new JobsProperties());

    user = new User();
    user.setId(1L);
    user.setEmail("owner@example.com");

    Album album = new Album();
    album.setId(7L);
    album.setUser(user);

    file = new FileMetadata();
    file.setId(FILE_ID);
    file.setAlbum(album);
    file.setStoredFilename("photo.jpg");

    when(userContext.getCurrentUser()).thenReturn(user);
    when(metaRepo.findByIdAndUserId(FILE_ID, user.getId())).thenReturn(Optional.of(file));
    when(imageTagRepo.findByFileMetadataId(FILE_ID)).thenReturn(List.of());
    // The response is built from the entity, so echoing the caption back is enough to assert on.
    when(mapper.fileMetadataToFileInfo(any(FileMetadata.class)))
        .thenAnswer(
            invocation -> {
              FileInfo info = new FileInfo();
              info.setCaption(invocation.<FileMetadata>getArgument(0).getCaption());
              return info;
            });
  }

  @Test
  void storesTheCaptionAndReturnsTheUpdatedAsset() {
    FileInfo updated = svc.updateCaption(FILE_ID, "  Sunrise over the fjord  ");

    // Stripped, so leading whitespace from a phone keyboard does not become part of the text.
    assertEquals("Sunrise over the fjord", file.getCaption());
    assertEquals("Sunrise over the fjord", updated.getCaption());
    verify(metaRepo).save(file);
  }

  @Test
  void blankClearsTheCaptionRatherThanStoringAnEmptyString() {
    file.setCaption("Something older");

    svc.updateCaption(FILE_ID, "   ");

    assertNull(file.getCaption());
  }

  @Test
  void nullClearsTheCaptionToo() {
    file.setCaption("Something older");

    svc.updateCaption(FILE_ID, null);

    assertNull(file.getCaption());
  }

  @Test
  void rejectsACaptionLongerThanTheCap() {
    assertThrows(ValidationException.class, () -> svc.updateCaption(FILE_ID, "x".repeat(2001)));
    verify(metaRepo, never()).save(any());
  }

  @Test
  void refusesAnAssetThatIsNotTheCallersOwn() {
    when(metaRepo.findByIdAndUserId(999L, user.getId())).thenReturn(Optional.empty());

    assertThrows(ResourceNotFoundException.class, () -> svc.updateCaption(999L, "Nice try"));
    verify(metaRepo, never()).save(any());
  }
}
