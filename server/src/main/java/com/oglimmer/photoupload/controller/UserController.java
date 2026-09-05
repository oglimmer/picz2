/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.ChangePasswordRequest;
import com.oglimmer.photoupload.model.CreateUserRequest;
import com.oglimmer.photoupload.model.CreateUserResponse;
import com.oglimmer.photoupload.model.PasswordResetRequest;
import com.oglimmer.photoupload.model.PasswordResetRequestRequest;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.service.UserService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/users")
@Slf4j
@RequiredArgsConstructor
public class UserController {

  private final UserService userService;
  private final UserContext userContext;

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

  // The three account-scoped routes below read the principal from the security context: Spring
  // Security has already authenticated the request, so re-decoding the Basic header here was a
  // second copy of that logic with its own failure modes.
  @PostMapping("/resend-verification")
  public ResponseEntity<Void> resendVerificationEmail() {
    userService.resendVerificationEmail(currentEmail());
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
  public ResponseEntity<Void> changePassword(@RequestBody ChangePasswordRequest req) {
    userService.changePassword(currentEmail(), req.getCurrentPassword(), req.getNewPassword());
    return ResponseEntity.ok().build();
  }

  @DeleteMapping("/account")
  public ResponseEntity<Void> deleteAccount() {
    userService.deleteAccount(currentEmail());
    return ResponseEntity.ok().build();
  }

  private String currentEmail() {
    return userContext.getCurrentUser().getEmail();
  }
}
