/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

class FileStorageServicePathTest {

  @Test
  void resolveFilePathBuildsAbsolutePath(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    FileMetadataRepository metaRepo = Mockito.mock(FileMetadataRepository.class);
    TagRepository tagRepo = Mockito.mock(TagRepository.class);
    ImageTagRepository imageTagRepo = Mockito.mock(ImageTagRepository.class);
    AlbumEnabledTagRepository albumEnabledTagRepo = Mockito.mock(AlbumEnabledTagRepository.class);
    ThumbnailService thumbSvc = Mockito.mock(ThumbnailService.class);
    JdbcTemplate jdbc = Mockito.mock(JdbcTemplate.class);
    AlbumRepository albumRepo = Mockito.mock(AlbumRepository.class);
    FileInfoMapper fileInfoMapper = Mockito.mock(FileInfoMapper.class);
    UserContext userContext = Mockito.mock(UserContext.class);
    PlatformTransactionManager txManager = Mockito.mock(PlatformTransactionManager.class);
    FileProcessingService fileProcessingService = Mockito.mock(FileProcessingService.class);

    FileStorageService svc =
        new FileStorageService(
            props,
            metaRepo,
            tagRepo,
            imageTagRepo,
            albumEnabledTagRepo,
            thumbSvc,
            jdbc,
            albumRepo,
            fileInfoMapper,
            userContext,
            txManager,
            fileProcessingService);

    // Not required for this specific test, but safe to ensure directory exists
    svc.init();

    Path resolved = svc.resolveFilePath("foo/bar.jpg");
    assertEquals(tempDir.resolve("foo/bar.jpg").toAbsolutePath().normalize(), resolved);
  }
}
