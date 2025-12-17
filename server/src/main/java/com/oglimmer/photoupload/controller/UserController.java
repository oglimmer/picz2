/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.ChangePasswordRequest;
import com.oglimmer.photoupload.model.CreateUserRequest;
import com.oglimmer.photoupload.model.CreateUserResponse;
import com.oglimmer.photoupload.model.PasswordResetRequest;
import com.oglimmer.photoupload.model.PasswordResetRequestRequest;
import com.oglimmer.photoupload.service.UserService;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
@Slf4j
@RequiredArgsConstructor
public class UserController {

  private final UserService userService;

  @PostMapping
  public ResponseEntity<CreateUserResponse> createUser(@RequestBody CreateUserRequest req) {
    User created = userService.createUser(req.getEmail(), req.getPassword());

    CreateUserResponse response =
        CreateUserResponse.builder().success(true).email(created.getEmail()).build();

    return ResponseEntity.status(HttpStatus.CREATED).body(response);
  }

  @GetMapping("/verify-email")
  public ResponseEntity<Void> verifyEmail(@RequestParam String token) {
    userService.verifyEmail(token);
    return ResponseEntity.ok().build();
  }

  @PostMapping("/resend-verification")
  public ResponseEntity<Void> resendVerificationEmail(HttpServletRequest request) {
    String email = extractEmailFromAuthHeader(request);
    if (email == null) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }

    userService.resendVerificationEmail(email);
    return ResponseEntity.ok().build();
  }

  @PostMapping("/password-reset-request")
  public ResponseEntity<Void> requestPasswordReset(@RequestBody PasswordResetRequestRequest req) {
    userService.requestPasswordReset(req.getEmail());
    return ResponseEntity.ok().build();
  }

  @PostMapping("/password-reset")
  public ResponseEntity<Void> resetPassword(@RequestBody PasswordResetRequest req) {
    userService.resetPassword(req.getToken(), req.getNewPassword());
    return ResponseEntity.ok().build();
  }

  @PostMapping("/change-password")
  public ResponseEntity<Void> changePassword(
      @RequestBody ChangePasswordRequest req, HttpServletRequest request) {
    String email = extractEmailFromAuthHeader(request);
    if (email == null) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }

    userService.changePassword(email, req.getCurrentPassword(), req.getNewPassword());
    return ResponseEntity.ok().build();
  }

  @DeleteMapping("/account")
  public ResponseEntity<Void> deleteAccount(HttpServletRequest request) {
    String email = extractEmailFromAuthHeader(request);
    if (email == null) {
      return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }

    userService.deleteAccount(email);
    return ResponseEntity.ok().build();
  }

  private String extractEmailFromAuthHeader(HttpServletRequest request) {
    String authHeader = request.getHeader("Authorization");
    if (authHeader != null && authHeader.startsWith("Basic ")) {
      try {
        String base64Credentials = authHeader.substring("Basic ".length());
        String credentials =
            new String(Base64.getDecoder().decode(base64Credentials), StandardCharsets.UTF_8);
        int idx = credentials.indexOf(":");
        if (idx > 0) {
          return credentials.substring(0, idx);
        }
      } catch (Exception ignored) {
      }
    }
    return null;
  }
}
