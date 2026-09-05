/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.SessionToken;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.SessionTokenRepository;
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
 * Issues, resolves and revokes browser session tokens (D78).
 *
 * <p>Same rules as {@link UploadTokenService}, and for the same reasons: the plaintext is returned
 * once and only its SHA-256 is stored; every token expires; a wrong token is a missing row, not a
 * comparison against a secret. Plain SHA-256 rather than a password hash because the token is 256
 * bits of {@link SecureRandom} — there is no dictionary to attack.
 *
 * <p>What is different from an upload token is the scope: a session token is a full login. That is
 * why it lives in the browser's {@code localStorage} in place of the password and not next to it,
 * and why {@link UserService} revokes every session on a password change.
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class SessionTokenService {

  /** Distinguishes a session token from an upload token ({@code zut_}) and from anything else. */
  public static final String TOKEN_PREFIX = "zst_";

  private static final SecureRandom RANDOM = new SecureRandom();

  private final SessionTokenRepository sessionTokenRepository;

  @Value("${session-tokens.ttl-days:30}")
  private int ttlDays;

  /** Mints a session for this user and returns the plaintext exactly once. Sweeps expired rows. */
  @Transactional
  public IssuedToken issue(User user) {
    int swept = sessionTokenRepository.deleteExpired(Instant.now());
    if (swept > 0) {
      log.debug("Swept {} expired session tokens", swept);
    }

    byte[] raw = new byte[32];
    RANDOM.nextBytes(raw);
    String token = TOKEN_PREFIX + Base64.getUrlEncoder().withoutPadding().encodeToString(raw);

    Instant now = Instant.now();
    Instant expiresAt = now.plus(Duration.ofDays(ttlDays));
    sessionTokenRepository.save(
        SessionToken.builder()
            .tokenHash(hash(token))
            .user(user)
            .createdAt(now)
            .expiresAt(expiresAt)
            .build());

    log.info("Issued session token for user {} valid until {}", user.getEmail(), expiresAt);
    return new IssuedToken(token, expiresAt);
  }

  /** True when this bearer value is one of ours, so the filter can ignore everything else. */
  public static boolean looksLikeToken(String value) {
    return value != null && value.startsWith(TOKEN_PREFIX);
  }

  /** Resolves a token to its owner, or empty when it is unknown or expired. */
  @Transactional(readOnly = true)
  public Optional<User> resolve(String token) {
    if (!looksLikeToken(token)) {
      return Optional.empty();
    }
    return sessionTokenRepository
        .findByTokenHash(hash(token))
        .filter(candidate -> candidate.getExpiresAt().isAfter(Instant.now()))
        .map(SessionToken::getUser);
  }

  /** Logout: the one session the browser presented. Unknown tokens are a no-op. */
  @Transactional
  public void revoke(String token) {
    if (!looksLikeToken(token)) {
      return;
    }
    sessionTokenRepository.deleteByTokenHash(hash(token));
  }

  /** Every session of the account — on password change and reset. */
  @Transactional
  public int revokeAllFor(Long userId) {
    return sessionTokenRepository.deleteByUserId(userId);
  }

  private static String hash(String token) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      return HexFormat.of().formatHex(digest.digest(token.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException("SHA-256 unavailable", e);
    }
  }

  /** The plaintext token and when it stops working. Returned to the client, never persisted. */
  public record IssuedToken(String token, Instant expiresAt) {}
}
