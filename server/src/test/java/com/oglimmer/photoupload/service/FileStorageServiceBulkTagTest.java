/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

/** Covers the album-wide add/remove used by the gallery's "Tag All as all" button. */
class FileStorageServiceBulkTagTest {

  private static final long ALBUM_ID = 7L;

  private FileMetadataRepository metaRepo;
  private TagRepository tagRepo;
  private ImageTagRepository imageTagRepo;
  private AlbumEnabledTagRepository albumEnabledTagRepo;
  private AlbumRepository albumRepo;
  private SystemTagProvisioner systemTagProvisioner;
  private FileStorageService svc;

  private User user;
  private Album album;
  private Tag allTag;
  private Tag noTag;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = Mockito.mock(FileMetadataRepository.class);
    tagRepo = Mockito.mock(TagRepository.class);
    imageTagRepo = Mockito.mock(ImageTagRepository.class);
    albumEnabledTagRepo = Mockito.mock(AlbumEnabledTagRepository.class);
    albumRepo = Mockito.mock(AlbumRepository.class);
    systemTagProvisioner = Mockito.mock(SystemTagProvisioner.class);
    UserContext userContext = Mockito.mock(UserContext.class);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            tagRepo,
            imageTagRepo,
            albumEnabledTagRepo,
            Mockito.mock(LocalFileCleanupService.class),
            Mockito.mock(JdbcTemplate.class),
            albumRepo,
            Mockito.mock(SlideshowRecordingRepository.class),
            Mockito.mock(FileInfoMapper.class),
            userContext,
            Mockito.mock(PlatformTransactionManager.class),
            Mockito.mock(JobEnqueueService.class),
            systemTagProvisioner,
            Optional.empty());

    user = new User();
    user.setId(1L);
    user.setEmail("owner@example.com");

    album = new Album();
    album.setId(ALBUM_ID);
    album.setUser(user);
    album.setName("Holiday");

    allTag = tag(10L, FileStorageService.ALL_TAG);
    noTag = tag(11L, FileStorageService.NO_TAG);

    when(userContext.getCurrentUser()).thenReturn(user);
    when(albumRepo.findByUserAndId(user, ALBUM_ID)).thenReturn(Optional.of(album));
    when(tagRepo.findByUserAndName(user, FileStorageService.ALL_TAG))
        .thenReturn(Optional.of(allTag));
    when(tagRepo.findByUserAndName(user, FileStorageService.NO_TAG)).thenReturn(Optional.of(noTag));
    // no_tag is now provisioned in its own transaction and resolved by id, not re-queried.
    when(systemTagProvisioner.ensureTag(user, FileStorageService.NO_TAG)).thenReturn(noTag.getId());
    when(tagRepo.getReferenceById(noTag.getId())).thenReturn(noTag);
  }

  @Test
  void addSkipsFilesThatAlreadyHaveTheTagAndDropsNoTag() {
    FileMetadata untagged = file(100L, noTag);
    FileMetadata tagged = file(101L, allTag);
    FileMetadata staleNoTag = file(102L, noTag, tag(12L, "beach"));
    givenAlbumFiles(untagged, tagged, staleNoTag);

    int changed = svc.addTagToAllFilesInAlbum(ALBUM_ID, FileStorageService.ALL_TAG);

    assertEquals(2, changed);
    ArgumentCaptor<ImageTag> saved = ArgumentCaptor.forClass(ImageTag.class);
    verify(imageTagRepo, times(2)).save(saved.capture());
    assertEquals(
        List.of(100L, 102L),
        saved.getAllValues().stream().map(it -> it.getFileMetadata().getId()).toList());
    // Assert on the fetched collection, not on repository.delete: it is mapped cascade-ALL +
    // orphanRemoval, so the collection is what decides which rows survive the flush.
    assertEquals(List.of(FileStorageService.ALL_TAG), tagNames(untagged));
    assertEquals(List.of(FileStorageService.ALL_TAG), tagNames(tagged));
    // Stale no_tag next to a real tag is healed, not preserved.
    assertEquals(List.of("beach", FileStorageService.ALL_TAG), tagNames(staleNoTag));
  }

  @Test
  void addRejectsNonSystemTagThatIsNotEnabledForTheAlbum() {
    Tag beach = tag(12L, "beach");
    when(tagRepo.findByUserAndName(user, "beach")).thenReturn(Optional.of(beach));
    when(albumEnabledTagRepo.existsByAlbumIdAndTagId(ALBUM_ID, beach.getId())).thenReturn(false);

    assertThrows(ValidationException.class, () -> svc.addTagToAllFilesInAlbum(ALBUM_ID, "beach"));
    verify(imageTagRepo, never()).save(any());
  }

  @Test
  void removeSkipsFilesWithoutTheTagAndRestoresNoTag() {
    FileMetadata onlyAll = file(100L, allTag);
    FileMetadata allPlusBeach = file(101L, allTag, tag(12L, "beach"));
    FileMetadata withoutAll = file(102L, tag(12L, "beach"));
    givenAlbumFiles(onlyAll, allPlusBeach, withoutAll);

    int changed = svc.removeTagFromAllFilesInAlbum(ALBUM_ID, FileStorageService.ALL_TAG);

    assertEquals(2, changed);
    // The tag is gone from the collection, which is what orphanRemoval acts on.
    assertEquals(List.of(FileStorageService.NO_TAG), tagNames(onlyAll));
    assertEquals(List.of("beach"), tagNames(allPlusBeach));
    assertEquals(List.of("beach"), tagNames(withoutAll));
    // Only the file left with no real tag gets no_tag back.
    ArgumentCaptor<ImageTag> saved = ArgumentCaptor.forClass(ImageTag.class);
    verify(imageTagRepo, times(1)).save(saved.capture());
    assertEquals(100L, saved.getValue().getFileMetadata().getId());
    assertEquals(FileStorageService.NO_TAG, saved.getValue().getTag().getName());
  }

  private static List<String> tagNames(FileMetadata metadata) {
    return metadata.getImageTags().stream().map(it -> it.getTag().getName()).toList();
  }

  private void givenAlbumFiles(FileMetadata... files) {
    when(metaRepo.findByAlbumIdAndUserIdWithTagsOrderByDisplayOrderAsc(ALBUM_ID, user.getId()))
        .thenReturn(List.of(files));
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
