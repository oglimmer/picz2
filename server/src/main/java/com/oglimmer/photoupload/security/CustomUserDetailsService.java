/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.security;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.UserRepository;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class CustomUserDetailsService implements UserDetailsService {

  /** Role names without the {@code ROLE_} prefix — Spring adds it in {@code roles(...)}. */
  public static final String ROLE_USER = "USER";

  public static final String ROLE_ADMIN = "ADMIN";

  private final UserRepository userRepository;

  @Override
  public UserDetails loadUserByUsername(String email) throws UsernameNotFoundException {
    User user =
        userRepository
            .findByEmail(email)
            .orElseThrow(
                () -> new UsernameNotFoundException("User not found with email: " + email));

    // Every account is a USER; the operator flag adds ADMIN, which gates /api/admin/** (D74).
    List<String> roles = user.isAdmin() ? List.of(ROLE_USER, ROLE_ADMIN) : List.of(ROLE_USER);
    return org.springframework.security.core.userdetails.User.withUsername(user.getEmail())
        .password(user.getPassword())
        .roles(roles.toArray(String[]::new))
        .build();
  }
}
