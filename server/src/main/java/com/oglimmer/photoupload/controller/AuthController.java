/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.AuthCheckResponse;
import com.oglimmer.photoupload.repository.UserRepository;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

  private final UserRepository userRepository;

  @GetMapping("/check")
  public ResponseEntity<AuthCheckResponse> checkAuth(HttpServletRequest request) {
    // If the request reached here, BasicAuthFilter validated credentials already.
    String authHeader = request.getHeader("Authorization");
    String email = null;
    boolean emailVerified = false;

    if (authHeader != null && authHeader.startsWith("Basic ")) {
      try {
        String base64Credentials = authHeader.substring("Basic ".length());
        String credentials =
            new String(Base64.getDecoder().decode(base64Credentials), StandardCharsets.UTF_8);
        int idx = credentials.indexOf(":");
        if (idx > 0) {
          email = credentials.substring(0, idx);
          // Look up user to get email verification status
          User user = userRepository.findByEmail(email).orElse(null);
          if (user != null) {
            emailVerified = user.isEmailVerified();
          }
        }
      } catch (Exception ignored) {
      }
    }

    AuthCheckResponse response =
        AuthCheckResponse.builder().success(true).email(email).emailVerified(emailVerified).build();

    return ResponseEntity.ok(response);
  }
}
