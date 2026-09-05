/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.DuplicateResourceException;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.TagMapper;
import com.oglimmer.photoupload.model.TagInfo;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The user's own tag list. API-only: it re-hides files through {@link SystemTagProvisioner}, which
 * exists on the api pod alone, and nothing on the worker edits tags.
 */
@Service
@Profile(Profiles.API)
@Slf4j
@RequiredArgsConstructor
public class TagService {

  private final TagRepository tagRepository;
  private final ImageTagRepository imageTagRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final SystemTagProvisioner systemTagProvisioner;
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
    if (SystemTags.isSystemTag(tagName)) {
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
    if (SystemTags.isSystemTag(tag.getName())) {
      throw new ValidationException(
          "The '" + tag.getName() + "' tag is a special system tag and cannot be modified");
    }

    // Prevent renaming to a reserved system tag name
    if (SystemTags.isSystemTag(newTagName)) {
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

    log.info("Updated tag: {} -> {} for user: {}", oldName, newTagName, currentUser.getEmail());

    return tagMapper.tagToTagInfo(tag);
  }

  @Transactional
  public void deleteTag(Long tagId) {
    User currentUser = userContext.getCurrentUser();
    Tag tag =
        tagRepository
            .findByUserAndId(currentUser, tagId)
            .orElseThrow(() -> new ResourceNotFoundException("Tag", "id", tagId));

    // Prevent deletion of special system tags
    if (SystemTags.isSystemTag(tag.getName())) {
      throw new ValidationException(
          "The '" + tag.getName() + "' tag is a special system tag and cannot be deleted");
    }

    // A file that carried only this tag would be left bare, and a bare file is a hidden one
    // (D79): put `hidden` on those before their last row goes, or deleting a tag would quietly
    // publish every photo that had nothing else.
    List<Long> leftBare = imageTagRepository.findFileIdsWhereTagIsTheOnlyOne(tagId);
    if (!leftBare.isEmpty()) {
      Tag hidden =
          tagRepository.getReferenceById(
              systemTagProvisioner.ensureTag(currentUser, SystemTags.HIDDEN));
      for (Long fileId : leftBare) {
        ImageTag row = new ImageTag();
        row.setFileMetadata(fileMetadataRepository.getReferenceById(fileId));
        row.setTag(hidden);
        imageTagRepository.save(row);
      }
      log.info(
          "Re-hid {} file(s) that carried only tag '{}' for user: {}",
          leftBare.size(),
          tag.getName(),
          currentUser.getEmail());
    }

    // Delete all associations with files
    imageTagRepository.deleteByTagId(tagId);

    // Delete the tag itself
    tagRepository.delete(tag);

    log.info("Deleted tag: {} for user: {}", tag.getName(), currentUser.getEmail());
  }
}
