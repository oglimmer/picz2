/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.AuthCheckResponse;
import com.oglimmer.photoupload.security.UserContext;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

  private final UserContext userContext;

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
}
