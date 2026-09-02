/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.UserRepository;
import com.oglimmer.photoupload.security.UserContext;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

// API-only: its one caller is SettingsController, and it now injects the API-scoped
// SystemTagProvisioner — without this the worker pod would fail to start on the missing bean.
@Profile(Profiles.API)
@Service
@Slf4j
@RequiredArgsConstructor
public class UserSettingService {

  private final UserRepository userRepository;
  private final AlbumRepository albumRepository;
  private final UserContext userContext;
  private final SystemTagProvisioner systemTagProvisioner;

  public Long getTargetAlbum() {
    User currentUser = userContext.getCurrentUser();
    return currentUser.getDefaultAlbumId();
  }

  @Transactional
  public void setTargetAlbum(Long albumId) {
    User currentUser = userContext.getCurrentUser();

    // Verify that the album exists and belongs to the user
    Album album =
        albumRepository
            .findByUserAndId(currentUser, albumId)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "id", albumId));

    currentUser.setDefaultAlbumId(albumId);
    userRepository.save(currentUser);

    log.info("Target album updated to: {} for user: {}", album.getName(), currentUser.getEmail());
  }

  @Transactional
  public void clearTargetAlbum() {
    User currentUser = userContext.getCurrentUser();

    currentUser.setDefaultAlbumId(null);
    userRepository.save(currentUser);

    log.info("Target album cleared (sync paused) for user: {}", currentUser.getEmail());
  }

  /**
   * The tag every newly registered asset of this user gets — {@code hidden} or {@code all} (D70).
   */
  public String getNewAssetTag() {
    return userContext.getCurrentUser().getNewAssetTag();
  }

  /**
   * Change which tag new assets get.
   *
   * <p>Switching to {@code all} makes every future upload public the moment it finishes processing,
   * so it is refused unless the caller passes {@code confirmed}. Switching back to {@code hidden}
   * only ever narrows what visitors can see and needs no confirmation.
   *
   * <p>Nothing already uploaded is re-tagged. The setting decides what happens next, and silently
   * pulling hundreds of live photos out of a shared album — or pushing them into one — is not
   * something a settings toggle should do.
   */
  @Transactional
  public void setNewAssetTag(String tagName, boolean confirmed) {
    if (tagName == null || !SystemTags.NEW_ASSET_CHOICES.contains(tagName)) {
      throw new ValidationException("New-asset tag must be one of " + SystemTags.NEW_ASSET_CHOICES);
    }
    if (SystemTags.ALL.equals(tagName) && !confirmed) {
      throw new ValidationException(
          "Switching to '"
              + SystemTags.ALL
              + "' publishes every future upload without review and must be confirmed");
    }

    User currentUser = userContext.getCurrentUser();

    // Provision the tag now rather than on the next upload. It costs one small insert and it means
    // the tag is already in the user's list when the UI re-reads it, so `hidden` is something they
    // can filter on and bulk-remove straight away instead of after the first photo lands.
    systemTagProvisioner.ensureTag(currentUser, tagName);

    currentUser.setNewAssetTag(tagName);
    userRepository.save(currentUser);

    log.info("New-asset tag set to '{}' for user: {}", tagName, currentUser.getEmail());
  }
}
