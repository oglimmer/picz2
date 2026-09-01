/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.repository.UserRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Lazily creates the per-user {@code all} system tag without letting a lost insert race kill the
 * caller's transaction.
 *
 * <p>Why this exists: system tags are created on first use, so a user's very first upload is the
 * one that creates them. The iOS share sheet fires several TUS post-finish hooks concurrently, so
 * for a brand-new user N requests all saw "tag missing", all inserted, one won, and the losers took
 * a {@code Duplicate entry '<uid>-all' for key 'uk_user_tag_name'}. That violation rolled back the
 * whole registration transaction, so the file_metadata row went with it and the photo silently
 * vanished. Observed 2026-08-28: 6 photos uploaded, 4 arrived, ids 6767/6768 burned.
 *
 * <p>The insert therefore runs in its OWN transaction (REQUIRES_NEW). A constraint violation there
 * poisons only that short-lived transaction; the caller's is untouched and can carry on. On a lost
 * race we re-read in yet another fresh transaction — required, not cosmetic: MariaDB defaults to
 * REPEATABLE READ, so the caller's already-open transaction holds a snapshot from before the winner
 * committed and would not see the row at all.
 *
 * <p>Returns the tag id rather than the entity, because the entity is managed by the throw-away
 * transaction. Callers turn it into a reference in their own context via {@code
 * tagRepository.getReferenceById(id)}, which never issues a SELECT and so never trips over that
 * same snapshot.
 */
@Service
@Profile(Profiles.API)
@Slf4j
public class SystemTagProvisioner {

  private final TagRepository tagRepository;
  private final UserRepository userRepository;
  private final TransactionTemplate ownTransaction;

  public SystemTagProvisioner(
      TagRepository tagRepository,
      UserRepository userRepository,
      PlatformTransactionManager transactionManager) {
    this.tagRepository = tagRepository;
    this.userRepository = userRepository;
    this.ownTransaction = new TransactionTemplate(transactionManager);
    this.ownTransaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
  }

  /** Convenience overload for callers that already hold the managed {@link User}. */
  public Long ensureTag(User user, String tagName) {
    return ensureTag(user.getId(), tagName);
  }

  /**
   * Return the id of {@code tagName} for {@code userId}, creating the row if it does not exist yet.
   * Safe to call concurrently for the same (user, tag) pair.
   */
  public Long ensureTag(Long userId, String tagName) {
    Long existing = findId(userId, tagName);
    if (existing != null) {
      return existing;
    }
    try {
      Long created =
          ownTransaction.execute(
              status -> {
                Tag tag = new Tag();
                tag.setUser(userRepository.getReferenceById(userId));
                tag.setName(tagName);
                return tagRepository.saveAndFlush(tag).getId();
              });
      log.info("Created special '{}' tag for user id {}", tagName, userId);
      return created;
    } catch (DataIntegrityViolationException e) {
      // Lost the race against a concurrent request for the same user. Its row is committed, so
      // re-read it in a fresh transaction and use the winner.
      Long winner = findId(userId, tagName);
      if (winner == null) {
        throw e;
      }
      log.debug("Lost '{}' creation race for user id {}; using tag {}", tagName, userId, winner);
      return winner;
    }
  }

  private Long findId(Long userId, String tagName) {
    return ownTransaction.execute(
        status -> tagRepository.findByUserIdAndName(userId, tagName).map(Tag::getId).orElse(null));
  }
}
