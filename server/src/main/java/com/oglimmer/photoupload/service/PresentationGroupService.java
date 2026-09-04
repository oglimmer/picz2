/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
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
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Presentation image groups — per (album, tag) section markers shown in presentation mode.
 *
 * <p>A group is anchored to one image; the client renders it as a heading in front of that image
 * and every following image until the group's end image (inclusive) or, when no end is set, until
 * the next anchor. Nothing here touches ordering: groups inherit the album's existing {@code
 * display_order}, so reordering images reshuffles the sections for free.
 *
 * <p>Because order lives in the images and not here, an end that has drifted in front of its own
 * start is not an error the server can see — the clients simply ignore an end they never reach,
 * and the group stays open-ended.
 */
@Profile(Profiles.API)
@Service
@Slf4j
@RequiredArgsConstructor
public class PresentationGroupService {

  private static final int MAX_LABEL_LENGTH = 120;
  private static final int MAX_TEXT_LENGTH = 4000;

  private final PresentationGroupRepository presentationGroupRepository;
  private final AlbumRepository albumRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final TagRepository tagRepository;
  private final PresentationGroupMapper presentationGroupMapper;
  private final UserContext userContext;

  /** All groups of an album, across every tag — the client filters by the selected tag. */
  @Transactional(readOnly = true)
  public List<PresentationGroupInfo> getAlbumGroups(Long albumId) {
    User currentUser = userContext.getCurrentUser();
    if (albumRepository.findByUserAndId(currentUser, albumId).isEmpty()) {
      throw new ResourceNotFoundException("Album not found with id: " + albumId);
    }

    return presentationGroupMapper.groupsToGroupInfos(
        presentationGroupRepository.findByAlbumIdOrderByStartFile(albumId));
  }

  /** Same list, reached through a public share link. Read-only by construction. */
  @Transactional(readOnly = true)
  public List<PresentationGroupInfo> getGroupsByShareToken(String shareToken) {
    Album album =
        albumRepository
            .findByShareTokenAndPublishedTrue(shareToken)
            .orElseThrow(() -> new ResourceNotFoundException("Album not found with share token"));

    return presentationGroupMapper.groupsToGroupInfos(
        presentationGroupRepository.findByAlbumIdOrderByStartFile(album.getId()));
  }

  @Transactional
  public PresentationGroupInfo createGroup(Long albumId, PresentationGroupRequest request) {
    User currentUser = userContext.getCurrentUser();
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(
                () -> new ResourceNotFoundException("Album not found with id: " + albumId));

    String label = normalizedLabel(request.getLabel());
    String text = normalizedText(request.getText());

    if (request.getTag() == null || request.getTag().isBlank()) {
      throw new ValidationException("Tag is required");
    }
    if (request.getStartFileId() == null) {
      throw new ValidationException("Start image is required");
    }

    Tag tag =
        tagRepository
            .findByUserAndName(currentUser, request.getTag().trim())
            .orElseThrow(
                () -> new ResourceNotFoundException("Tag not found: " + request.getTag().trim()));

    FileMetadata startFile =
        fileMetadataRepository
            .findById(request.getStartFileId())
            .orElseThrow(
                () ->
                    new ResourceNotFoundException(
                        "File not found with id: " + request.getStartFileId()));

    // The anchor has to live in the album the group belongs to, otherwise the section would
    // never render.
    if (startFile.getAlbum() == null || !startFile.getAlbum().getId().equals(album.getId())) {
      throw new ValidationException("Start image does not belong to album " + albumId);
    }

    if (presentationGroupRepository.existsByAlbumIdAndTagIdAndStartFileId(
        album.getId(), tag.getId(), startFile.getId())) {
      throw new DuplicateResourceException(
          "This image already starts a group for tag " + tag.getName());
    }

    PresentationGroup group = new PresentationGroup();
    group.setAlbum(album);
    group.setTag(tag);
    group.setStartFile(startFile);
    group.setEndFile(resolveEndFile(album, request.getEndFileId()));
    group.setLabel(label);
    group.setBodyText(text);

    group = presentationGroupRepository.save(group);

    log.info(
        "Created presentation group {} for album {} tag {} starting at file {}",
        group.getId(),
        album.getId(),
        tag.getName(),
        startFile.getId());

    return presentationGroupMapper.groupToGroupInfo(group);
  }

  /**
   * Only label and text are editable — moving a group means deleting it and creating a new one, and
   * the end marker has {@link #setGroupEnd} to itself.
   */
  @Transactional
  public PresentationGroupInfo updateGroup(Long groupId, PresentationGroupRequest request) {
    User currentUser = userContext.getCurrentUser();
    PresentationGroup group =
        presentationGroupRepository
            .findByIdAndUserId(groupId, currentUser.getId())
            .orElseThrow(
                () -> new ResourceNotFoundException("Group not found with id: " + groupId));

    group.setLabel(normalizedLabel(request.getLabel()));
    group.setBodyText(normalizedText(request.getText()));

    group = presentationGroupRepository.save(group);

    return presentationGroupMapper.groupToGroupInfo(group);
  }

  /**
   * Moves or clears the image a group stops at. A null {@code endFileId} reopens the group, so it
   * runs on until the next one starts again.
   */
  @Transactional
  public PresentationGroupInfo setGroupEnd(Long groupId, Long endFileId) {
    User currentUser = userContext.getCurrentUser();
    PresentationGroup group =
        presentationGroupRepository
            .findByIdAndUserId(groupId, currentUser.getId())
            .orElseThrow(
                () -> new ResourceNotFoundException("Group not found with id: " + groupId));

    group.setEndFile(resolveEndFile(group.getAlbum(), endFileId));
    group = presentationGroupRepository.save(group);

    log.info("Set end of presentation group {} to file {}", groupId, endFileId);

    return presentationGroupMapper.groupToGroupInfo(group);
  }

  /**
   * The end image, checked to live in the same album. Position is deliberately not checked: display
   * order can change under the group at any time, so "after the start" is not a durable invariant.
   */
  private FileMetadata resolveEndFile(Album album, Long endFileId) {
    if (endFileId == null) {
      return null;
    }

    FileMetadata endFile =
        fileMetadataRepository
            .findById(endFileId)
            .orElseThrow(
                () -> new ResourceNotFoundException("File not found with id: " + endFileId));

    if (endFile.getAlbum() == null || !endFile.getAlbum().getId().equals(album.getId())) {
      throw new ValidationException("End image does not belong to album " + album.getId());
    }

    return endFile;
  }

  @Transactional
  public void deleteGroup(Long groupId) {
    User currentUser = userContext.getCurrentUser();
    PresentationGroup group =
        presentationGroupRepository
            .findByIdAndUserId(groupId, currentUser.getId())
            .orElseThrow(
                () -> new ResourceNotFoundException("Group not found with id: " + groupId));

    presentationGroupRepository.delete(group);

    log.info("Deleted presentation group {}", groupId);
  }

  private String normalizedLabel(String label) {
    if (label == null || label.isBlank()) {
      throw new ValidationException("Label is required");
    }
    String trimmed = label.trim();
    if (trimmed.length() > MAX_LABEL_LENGTH) {
      throw new ValidationException("Label must be at most " + MAX_LABEL_LENGTH + " characters");
    }
    return trimmed;
  }

  /** Text is optional; blank collapses to null so the client can test one thing. */
  private String normalizedText(String text) {
    if (text == null || text.isBlank()) {
      return null;
    }
    String trimmed = text.trim();
    if (trimmed.length() > MAX_TEXT_LENGTH) {
      throw new ValidationException("Text must be at most " + MAX_TEXT_LENGTH + " characters");
    }
    return trimmed;
  }
}
