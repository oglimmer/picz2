/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.UploadToken;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.UploadTokenRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Issues and resolves scoped upload tokens (§5.9).
 *
 * <p>See {@link UploadToken} for why these exist. The rules that matter:
 *
 * <ul>
 *   <li>The plaintext token is returned once, at issue, and never stored — only its SHA-256.
 *   <li>Every token expires. A client that keeps one across a long background upload queue will
 *       eventually be refused and simply asks for another.
 *   <li>Resolution is constant-time-ish by construction: the lookup is by hash, so a wrong token is
 *       a missing row rather than a comparison against a secret.
 * </ul>
 *
 * <p>Plain SHA-256 rather than a password hash on purpose. A token is 256 bits of {@link
 * SecureRandom}, so there is no dictionary to attack and nothing for a slow KDF to buy; the hash
 * exists only so a database dump is not a bag of live credentials.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class UploadTokenService {

  /**
   * Marks a metadata auth value as a token rather than {@code email:password}.
   *
   * <p>Chosen to be impossible to confuse with an e-mail address, so {@link TusHookService} can
   * route the two formats apart with no ambiguity during the transition.
   */
  public static final String TOKEN_PREFIX = "zut_";

  private static final SecureRandom RANDOM = new SecureRandom();

  private final UploadTokenRepository uploadTokenRepository;

  @Value("${upload-tokens.ttl-hours:24}")
  private int ttlHours;

  /**
   * Mints a token for this user and returns the plaintext exactly once.
   *
   * <p>Sweeps expired rows on the way through: issuing is the only thing that grows this table, so
   * it is the natural place to shrink it, and that avoids a CronJob whose only job would be
   * deleting a handful of rows.
   */
  @Transactional
  public IssuedToken issue(User user) {
    int swept = uploadTokenRepository.deleteExpired(Instant.now());
    if (swept > 0) {
      log.debug("Swept {} expired upload tokens", swept);
    }

    byte[] raw = new byte[32];
    RANDOM.nextBytes(raw);
    String token = TOKEN_PREFIX + Base64.getUrlEncoder().withoutPadding().encodeToString(raw);

    Instant now = Instant.now();
    Instant expiresAt = now.plus(Duration.ofHours(ttlHours));
    uploadTokenRepository.save(
        UploadToken.builder()
            .tokenHash(hash(token))
            .user(user)
            .createdAt(now)
            .expiresAt(expiresAt)
            .build());

    log.info("Issued upload token for user {} valid until {}", user.getEmail(), expiresAt);
    return new IssuedToken(token, expiresAt);
  }

  /** True when this metadata auth value is a token rather than legacy {@code email:password}. */
  public static boolean looksLikeToken(String authValue) {
    return authValue != null && authValue.startsWith(TOKEN_PREFIX);
  }

  /**
   * Resolves a token to its owner, or empty when it is unknown or expired.
   *
   * <p>An expired row is left for the next sweep rather than deleted here: resolution runs inside
   * the tusd hook path, where a write is latency the upload does not need to pay.
   */
  @Transactional(readOnly = true)
  public Optional<User> resolve(String token) {
    if (!looksLikeToken(token)) {
      return Optional.empty();
    }
    return uploadTokenRepository
        .findByTokenHash(hash(token))
        .filter(candidate -> candidate.getExpiresAt().isAfter(Instant.now()))
        .map(UploadToken::getUser);
  }

  /** Invalidates every outstanding token for a user. */
  @Transactional
  public int revokeAllFor(Long userId) {
    return uploadTokenRepository.deleteByUserId(userId);
  }

  private static String hash(String token) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      return HexFormat.of().formatHex(digest.digest(token.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException e) {
      // SHA-256 is mandated by the JLS for every conforming JRE; unreachable in practice.
      throw new IllegalStateException("SHA-256 unavailable", e);
    }
  }

  /** The plaintext token and when it stops working. Returned to the client, never persisted. */
  public record IssuedToken(String token, Instant expiresAt) {}
}
