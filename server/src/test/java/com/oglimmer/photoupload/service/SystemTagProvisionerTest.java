/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.repository.UserRepository;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Regression cover for the 2026-08-28 data loss: a new user's concurrent first uploads each tried
 * to create {@code all}, the losers took a duplicate-key violation, and that violation rolled their
 * whole file_metadata insert back — two of six photos vanished. The provisioner must swallow the
 * lost race and hand back the winner's id instead of propagating the violation.
 */
class SystemTagProvisionerTest {

  private static final String ALL_TAG = FileStorageService.ALL_TAG;

  private TagRepository tagRepository;
  private UserRepository userRepository;
  private SystemTagProvisioner provisioner;
  private User user;

  @BeforeEach
  void setUp() {
    tagRepository = mock(TagRepository.class);
    userRepository = mock(UserRepository.class);
    provisioner =
        new SystemTagProvisioner(
            tagRepository, userRepository, mock(PlatformTransactionManager.class));

    user = new User();
    user.setId(3L);
    user.setEmail("test@oglimmer.com");
  }

  @Test
  void existingTagIsReusedWithoutInserting() {
    when(tagRepository.findByUserIdAndName(3L, ALL_TAG)).thenReturn(Optional.of(tag(39L)));

    assertEquals(39L, provisioner.ensureTag(user, ALL_TAG));
    verify(tagRepository, never()).saveAndFlush(any());
  }

  @Test
  void missingTagIsCreated() {
    when(tagRepository.findByUserIdAndName(3L, ALL_TAG)).thenReturn(Optional.empty());
    when(tagRepository.saveAndFlush(any(Tag.class))).thenReturn(tag(39L));

    assertEquals(39L, provisioner.ensureTag(user, ALL_TAG));
    verify(tagRepository).saveAndFlush(any(Tag.class));
  }

  @Test
  void lostInsertRaceReturnsTheWinnerInsteadOfThrowing() {
    // First read: nobody has the tag. Insert loses to a concurrent request. Second read (fresh
    // transaction, so the winner's commit is visible) finds it.
    when(tagRepository.findByUserIdAndName(3L, ALL_TAG))
        .thenReturn(Optional.empty())
        .thenReturn(Optional.of(tag(39L)));
    when(tagRepository.saveAndFlush(any(Tag.class)))
        .thenThrow(new DataIntegrityViolationException("Duplicate entry '3-all'"));

    assertEquals(39L, provisioner.ensureTag(user, ALL_TAG));
  }

  @Test
  void duplicateThatIsStillNotReadableRethrows() {
    DataIntegrityViolationException boom = new DataIntegrityViolationException("some other column");
    when(tagRepository.findByUserIdAndName(3L, ALL_TAG)).thenReturn(Optional.empty());
    when(tagRepository.saveAndFlush(any(Tag.class))).thenThrow(boom);

    assertSame(
        boom,
        assertThrows(
            DataIntegrityViolationException.class, () -> provisioner.ensureTag(user, ALL_TAG)));
  }

  private Tag tag(Long id) {
    Tag tag = new Tag();
    tag.setId(id);
    tag.setUser(user);
    tag.setName(ALL_TAG);
    return tag;
  }
}
