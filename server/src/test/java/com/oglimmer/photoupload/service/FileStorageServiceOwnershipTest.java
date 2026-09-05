/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The single-file mutations that used to be owner-blind. A file that belongs to another user must
 * be indistinguishable from a file that does not exist: same 404, no side effect.
 */
class FileStorageServiceOwnershipTest {

  private static final long USER_ID = 7L;
  private static final long OWN_FILE = 100L;
  private static final long FOREIGN_FILE = 200L;

  private FileMetadataRepository metaRepo;
  private JdbcTemplate jdbcTemplate;
  private FileStorageService svc;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = Mockito.mock(FileMetadataRepository.class);
    jdbcTemplate = Mockito.mock(JdbcTemplate.class);
    UserContext userContext = Mockito.mock(UserContext.class);

    User user = new User();
    user.setId(USER_ID);
    user.setEmail("owner@example.com");
    when(userContext.getCurrentUser()).thenReturn(user);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            Mockito.mock(TagRepository.class),
            Mockito.mock(ImageTagRepository.class),
            Mockito.mock(AlbumEnabledTagRepository.class),
            Mockito.mock(LocalFileCleanupService.class),
            jdbcTemplate,
            Mockito.mock(AlbumRepository.class),
            Mockito.mock(SlideshowRecordingRepository.class),
            Mockito.mock(StorageBackendRepository.class),
            Mockito.mock(FileInfoMapper.class),
            userContext,
            Mockito.mock(PlatformTransactionManager.class),
            Mockito.mock(JobEnqueueService.class),
            Mockito.mock(SystemTagProvisioner.class),
            Mockito.mock(StorageQuotaService.class),
            Optional.empty());
  }

  @Test
  void deleteFileRefusesAnotherUsersFile() {
    when(metaRepo.findByIdAndUserId(FOREIGN_FILE, USER_ID)).thenReturn(Optional.empty());

    assertThrows(ResourceNotFoundException.class, () -> svc.deleteFile(FOREIGN_FILE));

    verify(metaRepo, never()).findById(any());
    verify(metaRepo, never()).delete(any(FileMetadata.class));
  }

  @Test
  void deleteFileDeletesOwnFile() {
    FileMetadata own = new FileMetadata();
    own.setId(OWN_FILE);
    own.setStoredFilename("own.jpg");
    own.setFilePath("own.jpg");
    when(metaRepo.findByIdAndUserId(OWN_FILE, USER_ID)).thenReturn(Optional.of(own));
    when(metaRepo.countByFilePath("own.jpg")).thenReturn(1L);

    svc.deleteFile(OWN_FILE);

    verify(metaRepo).delete(own);
  }

  @Test
  void reorderRefusesWhenAnyIdBelongsToAnotherUser() {
    List<Long> requested = List.of(OWN_FILE, FOREIGN_FILE);
    when(metaRepo.findExistingIdsForUser(requested, USER_ID)).thenReturn(List.of(OWN_FILE));

    assertThrows(ResourceNotFoundException.class, () -> svc.reorderFiles(requested));

    verify(jdbcTemplate, never()).batchUpdate(anyString(), any(BatchPreparedStatementSetter.class));
  }

  @Test
  void reorderWritesWhenEveryIdIsOwned() {
    List<Long> requested = List.of(OWN_FILE, 101L);
    when(metaRepo.findExistingIdsForUser(requested, USER_ID)).thenReturn(List.of(OWN_FILE, 101L));

    svc.reorderFiles(requested);

    verify(jdbcTemplate)
        .batchUpdate(
            eq("UPDATE file_metadata SET display_order = ? WHERE id = ?"),
            any(BatchPreparedStatementSetter.class));
  }
}
