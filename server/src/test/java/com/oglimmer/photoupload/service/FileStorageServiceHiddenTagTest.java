/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
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
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The public side of D70: an asset carrying {@code hidden} must not reach a visitor through the
 * share token, either in the album listing or as a single image.
 *
 * <p>This is the security boundary of the whole feature. `/api/i/{token}` is deliberately NOT gated
 * — the owner's own gallery fetches pixels through it — so withholding the token here is what keeps
 * a hidden photo private.
 */
class FileStorageServiceHiddenTagTest {

  private static final String SHARE_TOKEN = "share-abc";

  private FileMetadataRepository metaRepo;
  private FileStorageService svc;

  private User user;
  private Album album;
  private Tag allTag;
  private Tag hiddenTag;
  private Tag beachTag;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = Mockito.mock(FileMetadataRepository.class);
    AlbumRepository albumRepo = Mockito.mock(AlbumRepository.class);
    FileInfoMapper mapper = Mockito.mock(FileInfoMapper.class);
    UserContext userContext = Mockito.mock(UserContext.class);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            Mockito.mock(TagRepository.class),
            Mockito.mock(ImageTagRepository.class),
            Mockito.mock(AlbumEnabledTagRepository.class),
            Mockito.mock(JdbcTemplate.class),
            albumRepo,
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

    album = new Album();
    album.setId(7L);
    album.setUser(user);
    album.setShareToken(SHARE_TOKEN);
    album.setPublished(true);
    // The published gate lives in the service now: an unpublished or unknown token is a 404.
    when(albumRepo.findByShareTokenAndPublishedTrue(SHARE_TOKEN)).thenReturn(Optional.of(album));

    allTag = tag(10L, SystemTags.ALL);
    hiddenTag = tag(11L, SystemTags.HIDDEN);
    beachTag = tag(12L, "beach");

    // The mapper is only asked to name the file, which is enough to tell the results apart.
    when(mapper.fileMetadataToFileInfo(Mockito.any()))
        .thenAnswer(
            invocation -> {
              FileMetadata source = invocation.getArgument(0);
              FileInfo info = new FileInfo();
              info.setId(source.getId());
              info.setTags(new ArrayList<>());
              return info;
            });
  }

  @Test
  void shareTokenListingDropsHiddenAssets() {
    FileMetadata visible = file(100L, allTag);
    FileMetadata held = file(101L, hiddenTag);
    // A hidden asset that also carries a real tag is still hidden: `hidden` wins over everything.
    FileMetadata heldButTagged = file(102L, hiddenTag, beachTag);
    FileMetadata untagged = file(103L);

    when(metaRepo.findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(SHARE_TOKEN))
        .thenReturn(List.of(visible, held, heldButTagged, untagged));

    List<Long> ids =
        svc.listFilesByAlbumByShareToken(SHARE_TOKEN).stream().map(FileInfo::getId).toList();

    assertEquals(List.of(100L, 103L), ids);
  }

  @Test
  void publicTokenLookupIs404ForAHiddenAsset() {
    FileMetadata held = file(101L, hiddenTag);
    when(metaRepo.findByPublicToken("tok-101")).thenReturn(Optional.of(held));

    assertThrows(ResourceNotFoundException.class, () -> svc.getFileInfoByPublicToken("tok-101"));
  }

  @Test
  void publicTokenLookupStillWorksForAVisibleAsset() {
    FileMetadata visible = file(100L, allTag);
    when(metaRepo.findByPublicToken("tok-100")).thenReturn(Optional.of(visible));

    assertEquals(100L, svc.getFileInfoByPublicToken("tok-100").getId());
  }

  private Tag tag(Long id, String name) {
    Tag tag = new Tag();
    tag.setId(id);
    tag.setUser(user);
    tag.setName(name);
    return tag;
  }

  private FileMetadata file(Long id, Tag... tags) {
    FileMetadata metadata = new FileMetadata();
    metadata.setId(id);
    metadata.setAlbum(album);
    metadata.setStoredFilename("file-" + id + ".jpg");
    metadata.setPublicToken("tok-" + id);
    List<ImageTag> imageTags = new ArrayList<>();
    for (Tag tag : tags) {
      ImageTag imageTag = new ImageTag();
      imageTag.setId(id * 10 + tag.getId());
      imageTag.setFileMetadata(metadata);
      imageTag.setTag(tag);
      imageTags.add(imageTag);
    }
    metadata.setImageTags(imageTags);
    return metadata;
  }
}
