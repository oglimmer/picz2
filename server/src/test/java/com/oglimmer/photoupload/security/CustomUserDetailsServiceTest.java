/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.security;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.UserRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;

@ExtendWith(MockitoExtension.class)
class CustomUserDetailsServiceTest {

  @Mock UserRepository userRepository;

  @InjectMocks CustomUserDetailsService service;

  @Test
  void loadsUserByEmail() {
    User u = new User();
    u.setEmail("a@b.com");
    u.setPassword("pw");
    when(userRepository.findByEmail("a@b.com")).thenReturn(Optional.of(u));

    UserDetails details = service.loadUserByUsername("a@b.com");
    assertEquals("a@b.com", details.getUsername());
    assertEquals("pw", details.getPassword());
  }

  @Test
  void throwsWhenMissing() {
    when(userRepository.findByEmail("x@y")).thenReturn(Optional.empty());
    assertThrows(UsernameNotFoundException.class, () -> service.loadUserByUsername("x@y"));
  }
}
