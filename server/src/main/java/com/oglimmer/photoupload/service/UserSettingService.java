/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.UserRepository;
import com.oglimmer.photoupload.security.UserContext;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class UserSettingService {

  private final UserRepository userRepository;
  private final AlbumRepository albumRepository;
  private final UserContext userContext;

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
}
