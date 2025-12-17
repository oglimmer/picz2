/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.security;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Component;

/** Utility class to extract the current authenticated user from the security context. */
@Component
@RequiredArgsConstructor
public class UserContext {

  private final UserRepository userRepository;

  /**
   * Gets the current authenticated user from the security context.
   *
   * @return the authenticated User entity
   * @throws UsernameNotFoundException if the user is not authenticated or not found
   */
  public User getCurrentUser() {
    Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

    if (authentication == null || !authentication.isAuthenticated()) {
      throw new UsernameNotFoundException("No authenticated user found");
    }

    String email = authentication.getName();

    return userRepository
        .findByEmail(email)
        .orElseThrow(() -> new UsernameNotFoundException("User not found with email: " + email));
  }

  /**
   * Gets the ID of the current authenticated user.
   *
   * @return the user ID
   * @throws UsernameNotFoundException if the user is not authenticated or not found
   */
  public Long getCurrentUserId() {
    return getCurrentUser().getId();
  }

  /**
   * Gets the email of the current authenticated user.
   *
   * @return the user email
   * @throws UsernameNotFoundException if the user is not authenticated
   */
  public String getCurrentUserEmail() {
    Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

    if (authentication == null || !authentication.isAuthenticated()) {
      throw new UsernameNotFoundException("No authenticated user found");
    }

    return authentication.getName();
  }
}
