/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.PresentationGroup;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.PresentationGroupMapper;
import com.oglimmer.photoupload.model.PresentationGroupInfo;
import com.oglimmer.photoupload.model.PresentationGroupRequest;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.PresentationGroupRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class PresentationGroupServiceTest {

  @Mock PresentationGroupRepository presentationGroupRepository;

  @Mock AlbumRepository albumRepository;

  @Mock FileMetadataRepository fileMetadataRepository;

  @Mock TagRepository tagRepository;

  @Mock PresentationGroupMapper presentationGroupMapper;

  @Mock UserContext userContext;

  @InjectMocks PresentationGroupService presentationGroupService;

  private User testUser;
  private Album album;
  private Tag tag;
  private FileMetadata file;

  @BeforeEach
  void setUp() {
    testUser = new User();
    testUser.setId(1L);
    testUser.setEmail("test@example.com");

    album = new Album();
    album.setId(10L);
    album.setUser(testUser);

    tag = new Tag();
    tag.setId(20L);
    tag.setName("rome");
    tag.setUser(testUser);

    file = new FileMetadata();
    file.setId(30L);
    file.setAlbum(album);
  }

  private PresentationGroupRequest request(String label, String text) {
    return new PresentationGroupRequest("rome", 30L, label, text);
  }

  private void stubHappyPathLookups() {
    when(userContext.getCurrentUser()).thenReturn(testUser);
    when(albumRepository.findByUserAndId(testUser, 10L)).thenReturn(Optional.of(album));
    when(tagRepository.findByUserAndName(testUser, "rome")).thenReturn(Optional.of(tag));
    when(fileMetadataRepository.findById(30L)).thenReturn(Optional.of(file));
  }

  @Test
  void createGroupPersistsLabelTagAndAnchor() {
    stubHappyPathLookups();
    when(presentationGroupRepository.existsByAlbumIdAndTagIdAndStartFileId(10L, 20L, 30L))
        .thenReturn(false);
    when(presentationGroupRepository.save(any(PresentationGroup.class)))
        .thenAnswer(inv -> inv.getArgument(0));
    when(presentationGroupMapper.groupToGroupInfo(any()))
        .thenReturn(PresentationGroupInfo.builder().id(99L).build());

    presentationGroupService.createGroup(10L, request("  Arrival  ", "  We landed at dusk.  "));

    ArgumentCaptor<PresentationGroup> captor = ArgumentCaptor.forClass(PresentationGroup.class);
    verify(presentationGroupRepository).save(captor.capture());
    PresentationGroup saved = captor.getValue();
    assertEquals("Arrival", saved.getLabel());
    assertEquals("We landed at dusk.", saved.getBodyText());
    assertEquals(album, saved.getAlbum());
    assertEquals(tag, saved.getTag());
    assertEquals(file, saved.getStartFile());
  }

  @Test
  void createGroupCollapsesBlankTextToNull() {
    stubHappyPathLookups();
    when(presentationGroupRepository.existsByAlbumIdAndTagIdAndStartFileId(10L, 20L, 30L))
        .thenReturn(false);
    when(presentationGroupRepository.save(any(PresentationGroup.class)))
        .thenAnswer(inv -> inv.getArgument(0));
    when(presentationGroupMapper.groupToGroupInfo(any()))
        .thenReturn(PresentationGroupInfo.builder().id(99L).build());

    presentationGroupService.createGroup(10L, request("Arrival", "   "));

    ArgumentCaptor<PresentationGroup> captor = ArgumentCaptor.forClass(PresentationGroup.class);
    verify(presentationGroupRepository).save(captor.capture());
    assertNull(captor.getValue().getBodyText());
  }

  @Test
  void createGroupRejectsBlankLabel() {
    when(userContext.getCurrentUser()).thenReturn(testUser);
    when(albumRepository.findByUserAndId(testUser, 10L)).thenReturn(Optional.of(album));

    ValidationException ex =
        assertThrows(
            ValidationException.class,
            () -> presentationGroupService.createGroup(10L, request("   ", null)));
    assertTrue(ex.getMessage().contains("Label is required"));
    verify(presentationGroupRepository, never()).save(any());
  }

  @Test
  void createGroupRejectsAnchorFromAnotherAlbum() {
    stubHappyPathLookups();
    Album otherAlbum = new Album();
    otherAlbum.setId(11L);
    file.setAlbum(otherAlbum);

    ValidationException ex =
        assertThrows(
            ValidationException.class,
            () -> presentationGroupService.createGroup(10L, request("Arrival", null)));
    assertTrue(ex.getMessage().contains("does not belong to album"));
    verify(presentationGroupRepository, never()).save(any());
  }

  @Test
  void createGroupRejectsSecondGroupOnSameAnchorAndTag() {
    stubHappyPathLookups();
    when(presentationGroupRepository.existsByAlbumIdAndTagIdAndStartFileId(10L, 20L, 30L))
        .thenReturn(true);

    assertThrows(
        DuplicateResourceException.class,
        () -> presentationGroupService.createGroup(10L, request("Arrival", null)));
    verify(presentationGroupRepository, never()).save(any());
  }

  @Test
  void createGroupRejectsUnknownTag() {
    when(userContext.getCurrentUser()).thenReturn(testUser);
    when(albumRepository.findByUserAndId(testUser, 10L)).thenReturn(Optional.of(album));
    when(tagRepository.findByUserAndName(testUser, "rome")).thenReturn(Optional.empty());

    assertThrows(
        ResourceNotFoundException.class,
        () -> presentationGroupService.createGroup(10L, request("Arrival", null)));
  }

  @Test
  void updateGroupChangesLabelAndTextOnly() {
    PresentationGroup existing = new PresentationGroup();
    existing.setId(99L);
    existing.setAlbum(album);
    existing.setTag(tag);
    existing.setStartFile(file);
    existing.setLabel("Old");
    existing.setBodyText("Old text");

    when(userContext.getCurrentUser()).thenReturn(testUser);
    when(presentationGroupRepository.findByIdAndUserId(99L, 1L)).thenReturn(Optional.of(existing));
    when(presentationGroupRepository.save(existing)).thenReturn(existing);
    when(presentationGroupMapper.groupToGroupInfo(existing))
        .thenReturn(PresentationGroupInfo.builder().id(99L).build());

    presentationGroupService.updateGroup(99L, request("New", "New text"));

    assertEquals("New", existing.getLabel());
    assertEquals("New text", existing.getBodyText());
    // The anchor never moves on update — that would need delete + create.
    assertEquals(file, existing.getStartFile());
    assertEquals(tag, existing.getTag());
  }

  @Test
  void deleteGroupRejectsGroupOwnedBySomeoneElse() {
    when(userContext.getCurrentUser()).thenReturn(testUser);
    when(presentationGroupRepository.findByIdAndUserId(99L, 1L)).thenReturn(Optional.empty());

    assertThrows(ResourceNotFoundException.class, () -> presentationGroupService.deleteGroup(99L));
    verify(presentationGroupRepository, never()).delete(any());
  }

  @Test
  void getAlbumGroupsRejectsAlbumNotOwnedByUser() {
    when(userContext.getCurrentUser()).thenReturn(testUser);
    when(albumRepository.findByUserAndId(testUser, 10L)).thenReturn(Optional.empty());

    assertThrows(
        ResourceNotFoundException.class, () -> presentationGroupService.getAlbumGroups(10L));
    verify(presentationGroupRepository, never()).findByAlbumIdOrderByStartFile(any());
  }
}
