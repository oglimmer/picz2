/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

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
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class TagService {

  private static final String NO_TAG = FileStorageService.NO_TAG;
  private static final String ALL_TAG = FileStorageService.ALL_TAG;

  private static boolean isSystemTag(String name) {
    return NO_TAG.equals(name) || ALL_TAG.equals(name);
  }

  private final TagRepository tagRepository;
  private final ImageTagRepository imageTagRepository;
  private final UserContext userContext;
  private final TagMapper tagMapper;

  @Transactional(readOnly = true)
  public List<TagInfo> getAllTags() {
    User currentUser = userContext.getCurrentUser();
    return tagMapper.tagsToTagInfos(tagRepository.findByUser(currentUser));
  }

  @Transactional
  public TagInfo createTag(String tagName) {
    User currentUser = userContext.getCurrentUser();

    // Prevent manual creation of special system tags
    if (isSystemTag(tagName)) {
      throw new ValidationException(
          "The '" + tagName + "' tag is a special system tag and cannot be manually created");
    }

    // Check if tag already exists for this user
    if (tagRepository.existsByUserAndName(currentUser, tagName)) {
      throw new DuplicateResourceException("Tag", "name", tagName);
    }

    // Validate tag name
    if (tagName.length() > 50) {
      throw new ValidationException("Tag name cannot exceed 50 characters");
    }

    Tag tag = new Tag();
    tag.setUser(currentUser);
    tag.setName(tagName);

    Tag savedTag = tagRepository.save(tag);
    log.info("Created tag: {} for user: {}", tagName, currentUser.getEmail());

    return tagMapper.tagToTagInfo(savedTag);
  }

  @Transactional
  public TagInfo updateTag(Long tagId, String newTagName) {
    User currentUser = userContext.getCurrentUser();
    Tag tag =
        tagRepository
            .findByUserAndId(currentUser, tagId)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "id", tagId));

    // Prevent modification of special system tags
    if (isSystemTag(tag.getName())) {
      throw new ValidationException(
          "The '" + tag.getName() + "' tag is a special system tag and cannot be modified");
    }

    // Prevent renaming to a reserved system tag name
    if (isSystemTag(newTagName)) {
      throw new ValidationException(
          "Cannot rename tag to '" + newTagName + "' as it is a reserved system tag name");
    }

    // Check if new name already exists for this user (and it's not the current tag)
    if (!tag.getName().equals(newTagName)
        && tagRepository.existsByUserAndName(currentUser, newTagName)) {
      throw new DuplicateResourceException("Tag", "name", newTagName);
    }

    // Validate tag name
    if (newTagName.length() > 50) {
      throw new ValidationException("Tag name cannot exceed 50 characters");
    }

    String oldName = tag.getName();
    tag.setName(newTagName);

    Tag updatedTag = tagRepository.save(tag);
    log.info("Updated tag: {} -> {} for user: {}", oldName, newTagName, currentUser.getEmail());

    return tagMapper.tagToTagInfo(updatedTag);
  }

  @Transactional
  public void deleteTag(Long tagId) {
    User currentUser = userContext.getCurrentUser();
    Tag tag =
        tagRepository
            .findByUserAndId(currentUser, tagId)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "id", tagId));

    // Prevent deletion of special system tags
    if (isSystemTag(tag.getName())) {
      throw new ValidationException(
          "The '" + tag.getName() + "' tag is a special system tag and cannot be deleted");
    }

    // Delete all associations with files first
    imageTagRepository.deleteByTagId(tagId);

    // Delete the tag itself
    tagRepository.delete(tag);

    log.info("Deleted tag: {} for user: {}", tag.getName(), currentUser.getEmail());
  }
}
