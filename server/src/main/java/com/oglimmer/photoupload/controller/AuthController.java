/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.AuthCheckResponse;
import com.oglimmer.photoupload.security.SessionTokenAuthenticationFilter;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.service.SessionTokenService;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

  private final UserContext userContext;
  private final SessionTokenService sessionTokenService;

  /**
   * Who am I. Reaching this handler means Spring Security already accepted the credentials, so the
   * principal is read from the security context rather than re-parsed out of the header.
   */
  @GetMapping("/check")
  public ResponseEntity<AuthCheckResponse> checkAuth() {
    User user = userContext.getCurrentUser();
    AuthCheckResponse response =
        AuthCheckResponse.builder()
            .success(true)
            .email(user.getEmail())
            .emailVerified(user.isEmailVerified())
            .admin(user.isAdmin())
            .build();
    return ResponseEntity.ok(response);
  }

  /**
   * Logs the browser in (D78). The request itself is Basic-authenticated — that is the one and
   * only time the web app sends the password — and the answer is a session token the browser
   * keeps instead of it. The same fields as {@code /check} ride along so the client needs one
   * round-trip, not two.
   */
  @PostMapping("/sessions")
  public ResponseEntity<SessionResponse> createSession() {
    User user = userContext.getCurrentUser();
    SessionTokenService.IssuedToken issued = sessionTokenService.issue(user);
    long expiresInSeconds =
        Math.max(0, Duration.between(Instant.now(), issued.expiresAt()).getSeconds());
    return ResponseEntity.ok(
        new SessionResponse(
            issued.token(),
            issued.expiresAt(),
            expiresInSeconds,
            user.getEmail(),
            user.isEmailVerified(),
            user.isAdmin()));
  }

  /**
   * Logs this browser out: the presented session token stops working. Other sessions of the same
   * account are untouched — a password change is what ends those. A Basic-authenticated call
   * presents no session and is a harmless no-op.
   */
  @DeleteMapping("/sessions/current")
  public ResponseEntity<Void> endSession(HttpServletRequest request) {
    String token = SessionTokenAuthenticationFilter.bearerToken(request);
    if (token != null) {
      sessionTokenService.revoke(token);
    }
    return ResponseEntity.noContent().build();
  }

  /**
   * @param token the plaintext session token — returned exactly once, never retrievable again
   * @param expiresAt absolute expiry
   * @param expiresInSeconds the same as a duration, immune to a skewed client clock
   */
  public record SessionResponse(
      String token,
      Instant expiresAt,
      long expiresInSeconds,
      String email,
      boolean emailVerified,
      boolean admin) {}
}
