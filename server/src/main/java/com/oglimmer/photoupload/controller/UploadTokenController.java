/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.service.UploadTokenService;
import java.time.Duration;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Hands an authenticated caller a scoped upload token (§5.9).
 *
 * <p>Requires normal authentication — the point is not to avoid logging in, it is to avoid carrying
 * the account password through a channel that persists it to storage. See {@link
 * com.oglimmer.photoupload.entity.UploadToken}.
 */
@Profile(Profiles.API)
@RestController
@RequestMapping("/api/upload-tokens")
@Slf4j
@RequiredArgsConstructor
public class UploadTokenController {

  private final UploadTokenService uploadTokenService;
  private final UserContext userContext;

  @PostMapping
  public ResponseEntity<UploadTokenResponse> issue() {
    UploadTokenService.IssuedToken issued = uploadTokenService.issue(userContext.getCurrentUser());
    long expiresInSeconds =
        Math.max(0, Duration.between(Instant.now(), issued.expiresAt()).getSeconds());
    return ResponseEntity.ok(
        new UploadTokenResponse(issued.token(), issued.expiresAt(), expiresInSeconds));
  }

  /**
   * @param token the plaintext token — returned exactly once, never retrievable again
   * @param expiresAt absolute expiry, for humans reading logs and for the web client
   * @param expiresInSeconds the same fact as a duration, which is what a client should actually
   *     schedule on: a phone with a skewed clock would refresh at the wrong moment, or never, if it
   *     compared the absolute timestamp against its own idea of now
   */
  public record UploadTokenResponse(String token, Instant expiresAt, long expiresInSeconds) {}
}
