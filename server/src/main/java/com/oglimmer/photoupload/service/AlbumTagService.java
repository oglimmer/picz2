/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AlbumEnabledTag;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.mapper.TagMapper;
import com.oglimmer.photoupload.model.TagInfo;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class AlbumTagService {

  private static final String NO_TAG = FileStorageService.NO_TAG;
  private static final String ALL_TAG = FileStorageService.ALL_TAG;

  private final AlbumRepository albumRepository;
  private final TagRepository tagRepository;
  private final AlbumEnabledTagRepository albumEnabledTagRepository;
  private final UserContext userContext;
  private final TagMapper tagMapper;

  @Transactional
  public List<TagInfo> getEnabledTags(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    Album album = requireOwnedAlbum(albumId);

    // The `all` system tag is always implicitly enabled for every album. Ensure it exists
    // and prepend it to the list so the frontend surfaces it in every album's pickers.
    Tag allTag = ensureSystemTag(currentUser, ALL_TAG);

    List<Tag> tags = new ArrayList<>();
    tags.add(allTag);
    albumEnabledTagRepository.findByAlbumId(album.getId()).stream()
        .map(AlbumEnabledTag::getTag)
        .filter(t -> !isSystemTag(t.getName()))
        .sorted((a, b) -> a.getName().compareToIgnoreCase(b.getName()))
        .forEach(tags::add);
    return tagMapper.tagsToTagInfos(tags);
  }

  @Transactional
  public List<TagInfo> setEnabledTags(Long albumId, List<Long> tagIds) {
    User currentUser = userContext.getCurrentUser();
    Album album = requireOwnedAlbum(albumId);

    Set<Long> desired = tagIds == null ? new HashSet<>() : new HashSet<>(tagIds);

    // Validate all requested tags belong to current user.
    // System tags (`no_tag`, `all`) are always implicitly enabled — no row is stored for them,
    // so silently drop their IDs from the incoming set if the client sent them.
    List<Tag> desiredTags = new ArrayList<>();
    for (Long tagId : desired) {
      Tag tag =
          tagRepository
              .findByUserAndId(currentUser, tagId)
              .orElseThrow(() -> new ResourceNotFoundException("Tag", "id", tagId));
      if (isSystemTag(tag.getName())) {
        continue;
      }
      desiredTags.add(tag);
    }

    List<AlbumEnabledTag> existing = albumEnabledTagRepository.findByAlbumId(album.getId());
    Set<Long> existingTagIds =
        existing.stream().map(a -> a.getTag().getId()).collect(Collectors.toSet());

    // Remove entries no longer desired
    for (AlbumEnabledTag entry : existing) {
      if (!desired.contains(entry.getTag().getId())) {
        albumEnabledTagRepository.delete(entry);
      }
    }

    // Add missing entries
    for (Tag tag : desiredTags) {
      if (!existingTagIds.contains(tag.getId())) {
        AlbumEnabledTag entry = new AlbumEnabledTag();
        entry.setAlbum(album);
        entry.setTag(tag);
        albumEnabledTagRepository.save(entry);
      }
    }

    log.info(
        "Set {} enabled tags on album '{}' for user: {}",
        desiredTags.size(),
        album.getName(),
        currentUser.getEmail());

    return getEnabledTags(albumId);
  }

  @Transactional(readOnly = true)
  public boolean isTagEnabledForAlbum(Long albumId, Long tagId) {
    return albumEnabledTagRepository.existsByAlbumIdAndTagId(albumId, tagId);
  }

  private Album requireOwnedAlbum(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    return albumRepository
        .findByUserAndId(currentUser, albumId)
        .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));
  }

  private Tag ensureSystemTag(User user, String name) {
    return tagRepository
        .findByUserAndName(user, name)
        .orElseGet(
            () -> {
              Tag tag = new Tag();
              tag.setUser(user);
              tag.setName(name);
              Tag saved = tagRepository.save(tag);
              log.info("Created special '{}' tag for user: {}", name, user.getEmail());
              return saved;
            });
  }

  private static boolean isSystemTag(String name) {
    return NO_TAG.equals(name) || ALL_TAG.equals(name);
  }
}
