/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.security;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.service.SessionTokenService;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;

/**
 * D78 — the filter that turns a bearer session token into a principal. It must accept exactly our
 * tokens, hand out the same roles the Basic path would, and stay out of the way of everything else.
 */
class SessionTokenAuthenticationFilterTest {

  SessionTokenService sessions;
  CustomUserDetailsService userDetails;
  SessionTokenAuthenticationFilter filter;

  @BeforeEach
  void setUp() {
    sessions = mock(SessionTokenService.class);
    userDetails = mock(CustomUserDetailsService.class);
    filter = new SessionTokenAuthenticationFilter(sessions, userDetails);
    SecurityContextHolder.clearContext();
  }

  @AfterEach
  void tearDown() {
    SecurityContextHolder.clearContext();
  }

  private MockHttpServletRequest request(String authorization) {
    MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/albums");
    if (authorization != null) {
      request.addHeader("Authorization", authorization);
    }
    return request;
  }

  private void run(MockHttpServletRequest request) throws Exception {
    filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());
  }

  @Test
  void aLiveTokenAuthenticatesWithTheUsersRoles() throws Exception {
    User user = new User();
    user.setEmail("ops@example.com");
    when(sessions.resolve("zst_live")).thenReturn(Optional.of(user));
    UserDetails details =
        org.springframework.security.core.userdetails.User.withUsername("ops@example.com")
            .password("n/a")
            .roles(CustomUserDetailsService.ROLE_USER, CustomUserDetailsService.ROLE_ADMIN)
            .build();
    when(userDetails.loadUserByUsername("ops@example.com")).thenReturn(details);

    run(request("Bearer zst_live"));

    Authentication auth = SecurityContextHolder.getContext().getAuthentication();
    assertNotNull(auth);
    assertEquals("ops@example.com", auth.getName());
    assertTrue(
        auth.getAuthorities().stream()
            .anyMatch(a -> a.getAuthority().equals("ROLE_" + CustomUserDetailsService.ROLE_ADMIN)));
  }

  @Test
  void anUnknownTokenLeavesTheRequestUnauthenticated() throws Exception {
    when(sessions.resolve("zst_stale")).thenReturn(Optional.empty());
    run(request("Bearer zst_stale"));
    assertNull(SecurityContextHolder.getContext().getAuthentication());
  }

  /** Basic (iOS, curl), a foreign bearer scheme and no header at all must not touch the service. */
  @Test
  void anythingButOurTokenPassesStraightThrough() throws Exception {
    run(request("Basic dXNlcjpwdw=="));
    run(request("Bearer eyJhbGciOi.notours"));
    run(request("Bearer zut_upload-token"));
    run(request(null));
    assertNull(SecurityContextHolder.getContext().getAuthentication());
    verifyNoInteractions(sessions, userDetails);
  }

  @Test
  void bearerTokenParsesCaseInsensitivelyAndTrims() {
    assertEquals("zst_x", SessionTokenAuthenticationFilter.bearerToken(request("bearer  zst_x ")));
    assertNull(SessionTokenAuthenticationFilter.bearerToken(request("Bearer other")));
    assertNull(SessionTokenAuthenticationFilter.bearerToken(request(null)));
  }
}
