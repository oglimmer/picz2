/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.UserRepository;
import com.oglimmer.photoupload.security.UserContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/** The per-user "what tag do new photos get" setting (D70). */
class UserSettingNewAssetTagTest {

  private UserRepository userRepository;
  private SystemTagProvisioner systemTagProvisioner;
  private UserSettingService svc;
  private User user;

  @BeforeEach
  void setUp() {
    userRepository = Mockito.mock(UserRepository.class);
    systemTagProvisioner = Mockito.mock(SystemTagProvisioner.class);
    UserContext userContext = Mockito.mock(UserContext.class);

    svc =
        new UserSettingService(
            userRepository, Mockito.mock(AlbumRepository.class), userContext, systemTagProvisioner);

    user = new User();
    user.setId(1L);
    user.setEmail("owner@example.com");
    when(userContext.getCurrentUser()).thenReturn(user);
  }

  @Test
  void freshUserHoldsNewPhotosBack() {
    assertEquals(SystemTags.HIDDEN, svc.getNewAssetTag());
  }

  @Test
  void switchingToAllNeedsConfirmation() {
    assertThrows(ValidationException.class, () -> svc.setNewAssetTag(SystemTags.ALL, false));

    assertEquals(SystemTags.HIDDEN, user.getNewAssetTag());
    verify(userRepository, never()).save(Mockito.any());
  }

  @Test
  void confirmedSwitchToAllIsStoredAndProvisionsTheTag() {
    svc.setNewAssetTag(SystemTags.ALL, true);

    assertEquals(SystemTags.ALL, user.getNewAssetTag());
    verify(systemTagProvisioner).ensureTag(user, SystemTags.ALL);
    verify(userRepository).save(user);
  }

  @Test
  void switchingBackToHiddenNeedsNoConfirmation() {
    user.setNewAssetTag(SystemTags.ALL);

    svc.setNewAssetTag(SystemTags.HIDDEN, false);

    assertEquals(SystemTags.HIDDEN, user.getNewAssetTag());
    verify(systemTagProvisioner).ensureTag(user, SystemTags.HIDDEN);
  }

  @Test
  void anyOtherTagNameIsRefused() {
    // The column is not a free-text "tag new photos with whatever": only the two system tags have
    // a meaning to the public listing, and an ordinary tag here would silently do nothing.
    assertThrows(ValidationException.class, () -> svc.setNewAssetTag("beach", true));
    assertThrows(ValidationException.class, () -> svc.setNewAssetTag(null, true));

    assertEquals(SystemTags.HIDDEN, user.getNewAssetTag());
  }
}
