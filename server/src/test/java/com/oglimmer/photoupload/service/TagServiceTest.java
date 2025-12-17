/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.TagMapper;
import com.oglimmer.photoupload.model.TagInfo;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class TagServiceTest {

  @Mock TagRepository tagRepository;

  @Mock ImageTagRepository imageTagRepository;

  @Mock UserContext userContext;

  @Mock TagMapper tagMapper;

  @InjectMocks TagService tagService;

  private User testUser;

  @BeforeEach
  void setUp() {
    testUser = new User();
    testUser.setId(1L);
    testUser.setEmail("test@example.com");
    when(userContext.getCurrentUser()).thenReturn(testUser);
  }

  @Test
  void getAllTagsDelegatesToRepository() {
    Tag t1 = new Tag();
    t1.setId(1L);
    t1.setName("one");
    t1.setUser(testUser);
    Tag t2 = new Tag();
    t2.setId(2L);
    t2.setName("two");
    t2.setUser(testUser);
    when(tagRepository.findByUser(testUser)).thenReturn(Arrays.asList(t1, t2));

    // Mock mapper
    TagInfo info1 = new TagInfo(1L, "one", null);
    TagInfo info2 = new TagInfo(2L, "two", null);
    when(tagMapper.tagsToTagInfos(Arrays.asList(t1, t2))).thenReturn(Arrays.asList(info1, info2));

    List<TagInfo> result = tagService.getAllTags();
    assertEquals(2, result.size());
    assertEquals("one", result.get(0).getName());
  }

  @Test
  void createTagThrowsWhenExists() {
    when(tagRepository.existsByUserAndName(testUser, "dup")).thenReturn(true);
    DuplicateResourceException ex =
        assertThrows(DuplicateResourceException.class, () -> tagService.createTag("dup"));
    assertTrue(ex.getMessage().contains("already exists"));
    verify(tagRepository, never()).save(any());
  }

  @Test
  void createTagThrowsWhenTooLong() {
    String longName = "x".repeat(51);
    when(tagRepository.existsByUserAndName(testUser, longName)).thenReturn(false);
    ValidationException ex =
        assertThrows(ValidationException.class, () -> tagService.createTag(longName));
    assertTrue(ex.getMessage().contains("exceed 50"));
  }

  @Test
  void createTagSavesAndReturns() {
    when(tagRepository.existsByUserAndName(testUser, "new")).thenReturn(false);
    Tag saved = new Tag();
    saved.setId(99L);
    saved.setName("new");
    saved.setUser(testUser);
    when(tagRepository.save(any(Tag.class))).thenReturn(saved);

    // Mock mapper
    TagInfo info = new TagInfo(99L, "new", null);
    when(tagMapper.tagToTagInfo(saved)).thenReturn(info);

    TagInfo result = tagService.createTag("new");
    assertEquals(99L, result.getId());
    assertEquals("new", result.getName());
  }

  @Test
  void updateTagThrowsWhenNotFound() {
    when(tagRepository.findByUserAndId(testUser, 1L)).thenReturn(Optional.empty());
    ResourceNotFoundException ex =
        assertThrows(ResourceNotFoundException.class, () -> tagService.updateTag(1L, "x"));
    assertTrue(ex.getMessage().contains("not found"));
  }

  @Test
  void updateTagThrowsWhenDuplicateName() {
    Tag existing = new Tag();
    existing.setId(1L);
    existing.setName("a");
    existing.setUser(testUser);
    when(tagRepository.findByUserAndId(testUser, 1L)).thenReturn(Optional.of(existing));
    when(tagRepository.existsByUserAndName(testUser, "b")).thenReturn(true);
    DuplicateResourceException ex =
        assertThrows(DuplicateResourceException.class, () -> tagService.updateTag(1L, "b"));
    assertTrue(ex.getMessage().contains("already exists"));
  }

  @Test
  void updateTagThrowsWhenTooLong() {
    Tag existing = new Tag();
    existing.setId(1L);
    existing.setName("a");
    existing.setUser(testUser);
    when(tagRepository.findByUserAndId(testUser, 1L)).thenReturn(Optional.of(existing));
    String longName = "y".repeat(51);
    ValidationException ex =
        assertThrows(ValidationException.class, () -> tagService.updateTag(1L, longName));
    assertTrue(ex.getMessage().contains("exceed 50"));
  }

  @Test
  void updateTagSavesNewName() {
    Tag existing = new Tag();
    existing.setId(1L);
    existing.setName("a");
    existing.setUser(testUser);
    when(tagRepository.findByUserAndId(testUser, 1L)).thenReturn(Optional.of(existing));
    when(tagRepository.existsByUserAndName(testUser, "b")).thenReturn(false);
    when(tagRepository.save(any(Tag.class))).thenAnswer(inv -> inv.getArgument(0));

    // Mock mapper
    TagInfo info = new TagInfo(1L, "b", null);
    when(tagMapper.tagToTagInfo(any(Tag.class))).thenReturn(info);

    TagInfo updated = tagService.updateTag(1L, "b");
    assertEquals("b", updated.getName());
    ArgumentCaptor<Tag> captor = ArgumentCaptor.forClass(Tag.class);
    verify(tagRepository).save(captor.capture());
    assertEquals("b", captor.getValue().getName());
  }

  @Test
  void deleteTagRemovesAssociationsAndEntity() {
    Tag tag = new Tag();
    tag.setId(42L);
    tag.setName("t");
    tag.setUser(testUser);
    when(tagRepository.findByUserAndId(testUser, 42L)).thenReturn(Optional.of(tag));

    tagService.deleteTag(42L);

    verify(imageTagRepository).deleteByTagId(42L);
    verify(tagRepository).delete(tag);
  }
}
