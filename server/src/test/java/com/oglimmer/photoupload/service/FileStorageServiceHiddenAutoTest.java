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
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ValidationException;
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

/**
 * D79: {@code hidden} is derived, not assigned. A file carries it exactly while it has no other
 * tag. These tests pin the four edges on the single-file and the album-wide paths: a real tag takes
 * {@code hidden} off, losing the last real tag puts it back, {@code hidden} cannot be added by
 * hand, and a lone {@code hidden} cannot be taken off by hand.
 */
class FileStorageServiceHiddenAutoTest {

  private static final long ALBUM_ID = 7L;
  private static final long FILE_ID = 100L;

  private FileMetadataRepository metaRepo;
  private TagRepository tagRepo;
  private ImageTagRepository imageTagRepo;
  private AlbumEnabledTagRepository albumEnabledTagRepo;
  private SystemTagProvisioner systemTagProvisioner;
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
    tagRepo = Mockito.mock(TagRepository.class);
    imageTagRepo = Mockito.mock(ImageTagRepository.class);
    albumEnabledTagRepo = Mockito.mock(AlbumEnabledTagRepository.class);
    AlbumRepository albumRepo = Mockito.mock(AlbumRepository.class);
    systemTagProvisioner = Mockito.mock(SystemTagProvisioner.class);
    UserContext userContext = Mockito.mock(UserContext.class);

    svc =
        new FileStorageService(
            props,
            metaRepo,
            tagRepo,
            imageTagRepo,
            albumEnabledTagRepo,
            Mockito.mock(JdbcTemplate.class),
            albumRepo,
            Mockito.mock(SlideshowRecordingRepository.class),
            Mockito.mock(StorageBackendRepository.class),
            Mockito.mock(FileInfoMapper.class),
            userContext,
            Mockito.mock(PlatformTransactionManager.class),
            Mockito.mock(JobEnqueueService.class),
            systemTagProvisioner,
            Mockito.mock(StorageQuotaService.class),
            Mockito.mock(ObjectStorageService.class));

    user = new User();
    user.setId(1L);
    user.setEmail("owner@example.com");

    album = new Album();
    album.setId(ALBUM_ID);
    album.setUser(user);
    album.setName("Holiday");

    allTag = tag(10L, SystemTags.ALL);
    hiddenTag = tag(11L, SystemTags.HIDDEN);
    beachTag = tag(12L, "beach");

    when(userContext.getCurrentUser()).thenReturn(user);
    when(albumRepo.findByUserAndId(user, ALBUM_ID)).thenReturn(Optional.of(album));
    when(tagRepo.findByUserAndName(user, SystemTags.ALL)).thenReturn(Optional.of(allTag));
    when(tagRepo.findByUserAndName(user, SystemTags.HIDDEN)).thenReturn(Optional.of(hiddenTag));
    when(tagRepo.findByUserAndName(user, "beach")).thenReturn(Optional.of(beachTag));
    when(tagRepo.getReferenceById(hiddenTag.getId())).thenReturn(hiddenTag);
    when(albumEnabledTagRepo.existsByAlbumIdAndTagId(ALBUM_ID, beachTag.getId())).thenReturn(true);
    when(systemTagProvisioner.ensureTag(user, SystemTags.HIDDEN)).thenReturn(hiddenTag.getId());
  }

  // --- one file --------------------------------------------------------------------------------

  @Test
  void addingARealTagTakesHiddenOff() {
    FileMetadata file = file(FILE_ID);
    when(metaRepo.findByIdAndUserId(FILE_ID, user.getId())).thenReturn(Optional.of(file));
    ImageTag hiddenRow = row(file, hiddenTag);
    when(imageTagRepo.findByFileMetadataIdAndTagId(FILE_ID, hiddenTag.getId()))
        .thenReturn(Optional.of(hiddenRow));
    when(imageTagRepo.findByFileMetadataIdAndTagId(FILE_ID, beachTag.getId()))
        .thenReturn(Optional.empty());
    when(imageTagRepo.findByFileMetadataId(FILE_ID)).thenReturn(List.of(row(file, beachTag)));

    List<String> tags = svc.addTagToFile(FILE_ID, "beach");

    assertEquals(List.of("beach"), tags);
    ArgumentCaptor<ImageTag> saved = ArgumentCaptor.forClass(ImageTag.class);
    verify(imageTagRepo).save(saved.capture());
    assertEquals("beach", saved.getValue().getTag().getName());
    verify(imageTagRepo).delete(hiddenRow);
  }

  @Test
  void addingARealTagToAFileThatIsNotHiddenDeletesNothing() {
    FileMetadata file = file(FILE_ID);
    when(metaRepo.findByIdAndUserId(FILE_ID, user.getId())).thenReturn(Optional.of(file));
    when(imageTagRepo.findByFileMetadataIdAndTagId(any(), any())).thenReturn(Optional.empty());
    when(imageTagRepo.findByFileMetadataId(FILE_ID))
        .thenReturn(List.of(row(file, allTag), row(file, beachTag)));

    List<String> tags = svc.addTagToFile(FILE_ID, "beach");

    assertEquals(List.of(SystemTags.ALL, "beach"), tags);
    verify(imageTagRepo, never()).delete(any(ImageTag.class));
  }

  @Test
  void hiddenCannotBeAddedByHand() {
    assertThrows(ValidationException.class, () -> svc.addTagToFile(FILE_ID, SystemTags.HIDDEN));
    verify(imageTagRepo, never()).save(any());
    // Refused before any lookup: the message is about the rule, not about a missing file.
    verify(metaRepo, never()).findByIdAndUserId(any(), any());
  }

  @Test
  void removingTheLastRealTagPutsHiddenBack() {
    FileMetadata file = file(FILE_ID);
    when(metaRepo.findByIdAndUserId(FILE_ID, user.getId())).thenReturn(Optional.of(file));
    ImageTag beachRow = row(file, beachTag);
    when(imageTagRepo.findByFileMetadataIdAndTagId(FILE_ID, beachTag.getId()))
        .thenReturn(Optional.of(beachRow));
    when(imageTagRepo.findByFileMetadataIdAndTagId(FILE_ID, hiddenTag.getId()))
        .thenReturn(Optional.empty());
    // First read: nothing left after the delete. Second read: the re-hidden state.
    when(imageTagRepo.findByFileMetadataId(FILE_ID))
        .thenReturn(List.of(), List.of(row(file, hiddenTag)));

    List<String> tags = svc.removeTagFromFile(FILE_ID, "beach");

    assertEquals(List.of(SystemTags.HIDDEN), tags);
    verify(imageTagRepo).delete(beachRow);
    ArgumentCaptor<ImageTag> saved = ArgumentCaptor.forClass(ImageTag.class);
    verify(imageTagRepo).save(saved.capture());
    assertEquals(SystemTags.HIDDEN, saved.getValue().getTag().getName());
    assertEquals(FILE_ID, saved.getValue().getFileMetadata().getId());
    verify(systemTagProvisioner).ensureTag(user, SystemTags.HIDDEN);
  }

  @Test
  void removingOneOfSeveralRealTagsLeavesTheFileAlone() {
    FileMetadata file = file(FILE_ID);
    when(metaRepo.findByIdAndUserId(FILE_ID, user.getId())).thenReturn(Optional.of(file));
    ImageTag beachRow = row(file, beachTag);
    when(imageTagRepo.findByFileMetadataIdAndTagId(FILE_ID, beachTag.getId()))
        .thenReturn(Optional.of(beachRow));
    when(imageTagRepo.findByFileMetadataId(FILE_ID)).thenReturn(List.of(row(file, allTag)));

    List<String> tags = svc.removeTagFromFile(FILE_ID, "beach");

    assertEquals(List.of(SystemTags.ALL), tags);
    verify(imageTagRepo).delete(beachRow);
    verify(imageTagRepo, never()).save(any());
    verify(systemTagProvisioner, never()).ensureTag(any(User.class), any());
  }

  @Test
  void aLoneHiddenCannotBeRemovedByHand() {
    FileMetadata file = file(FILE_ID);
    when(metaRepo.findByIdAndUserId(FILE_ID, user.getId())).thenReturn(Optional.of(file));
    ImageTag hiddenRow = row(file, hiddenTag);
    when(imageTagRepo.findByFileMetadataIdAndTagId(FILE_ID, hiddenTag.getId()))
        .thenReturn(Optional.of(hiddenRow));
    when(imageTagRepo.findByFileMetadataId(FILE_ID)).thenReturn(List.of(hiddenRow));

    ValidationException ex =
        assertThrows(
            ValidationException.class, () -> svc.removeTagFromFile(FILE_ID, SystemTags.HIDDEN));

    assertEquals(FileStorageService.HIDDEN_IS_THE_ONLY_TAG, ex.getMessage());
    verify(imageTagRepo, never()).delete(any(ImageTag.class));
  }

  @Test
  void hiddenNextToARealTagCanStillBeRemovedByHand() {
    // Older rows can carry `hidden` next to a real tag. Publishing those by hand keeps working.
    FileMetadata file = file(FILE_ID);
    when(metaRepo.findByIdAndUserId(FILE_ID, user.getId())).thenReturn(Optional.of(file));
    ImageTag hiddenRow = row(file, hiddenTag);
    ImageTag beachRow = row(file, beachTag);
    when(imageTagRepo.findByFileMetadataIdAndTagId(FILE_ID, hiddenTag.getId()))
        .thenReturn(Optional.of(hiddenRow));
    when(imageTagRepo.findByFileMetadataId(FILE_ID))
        .thenReturn(List.of(hiddenRow, beachRow), List.of(beachRow));

    List<String> tags = svc.removeTagFromFile(FILE_ID, SystemTags.HIDDEN);

    assertEquals(List.of("beach"), tags);
    verify(imageTagRepo).delete(hiddenRow);
    verify(imageTagRepo, never()).save(any());
  }

  // --- whole album -----------------------------------------------------------------------------

  @Test
  void bulkAddTakesHiddenOffEveryFileThatGetsTheTag() {
    FileMetadata held = file(100L, hiddenTag);
    FileMetadata heldButTagged = file(101L, hiddenTag, allTag);
    FileMetadata published = file(102L, allTag);
    givenAlbumFiles(held, heldButTagged, published);

    int changed = svc.addTagToAllFilesInAlbum(ALBUM_ID, SystemTags.ALL);

    // 100 gets `all` and loses `hidden`; 101 already had `all` but still loses `hidden`; 102 is
    // already exactly right.
    assertEquals(2, changed);
    assertEquals(List.of(SystemTags.ALL), tagNames(held));
    assertEquals(List.of(SystemTags.ALL), tagNames(heldButTagged));
    assertEquals(List.of(SystemTags.ALL), tagNames(published));
    verify(imageTagRepo, times(1)).save(any());
  }

  @Test
  void bulkAddRefusesHidden() {
    assertThrows(
        ValidationException.class, () -> svc.addTagToAllFilesInAlbum(ALBUM_ID, SystemTags.HIDDEN));
    verify(imageTagRepo, never()).save(any());
  }

  @Test
  void bulkRemoveReHidesOnlyTheFilesLeftBare() {
    FileMetadata onlyBeach = file(100L, beachTag);
    FileMetadata beachAndAll = file(101L, beachTag, allTag);
    FileMetadata untouched = file(102L, allTag);
    givenAlbumFiles(onlyBeach, beachAndAll, untouched);

    int changed = svc.removeTagFromAllFilesInAlbum(ALBUM_ID, "beach");

    assertEquals(2, changed);
    assertEquals(List.of(SystemTags.HIDDEN), tagNames(onlyBeach));
    assertEquals(List.of(SystemTags.ALL), tagNames(beachAndAll));
    assertEquals(List.of(SystemTags.ALL), tagNames(untouched));
    verify(imageTagRepo, times(1)).save(any());
  }

  @Test
  void bulkRemoveOfHiddenSkipsFilesWhereItIsTheOnlyTag() {
    FileMetadata loneHidden = file(100L, hiddenTag);
    FileMetadata hiddenAndBeach = file(101L, hiddenTag, beachTag);
    FileMetadata notHidden = file(102L, beachTag);
    givenAlbumFiles(loneHidden, hiddenAndBeach, notHidden);

    int changed = svc.removeTagFromAllFilesInAlbum(ALBUM_ID, SystemTags.HIDDEN);

    // Only 101 changes: 100 would get `hidden` straight back, 102 never had it.
    assertEquals(1, changed);
    assertEquals(List.of(SystemTags.HIDDEN), tagNames(loneHidden));
    assertEquals(List.of("beach"), tagNames(hiddenAndBeach));
    assertEquals(List.of("beach"), tagNames(notHidden));
    verify(imageTagRepo, never()).save(any());
  }

  // --- helpers ---------------------------------------------------------------------------------

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

  private static ImageTag row(FileMetadata file, Tag tag) {
    ImageTag imageTag = new ImageTag();
    imageTag.setId(file.getId() * 10 + tag.getId());
    imageTag.setFileMetadata(file);
    imageTag.setTag(tag);
    return imageTag;
  }

  private FileMetadata file(Long id, Tag... tags) {
    FileMetadata metadata = new FileMetadata();
    metadata.setId(id);
    metadata.setAlbum(album);
    metadata.setStoredFilename("file-" + id + ".jpg");
    List<ImageTag> imageTags = new ArrayList<>();
    for (Tag tag : tags) {
      imageTags.add(row(metadata, tag));
    }
    metadata.setImageTags(imageTags);
    return metadata;
  }
}
