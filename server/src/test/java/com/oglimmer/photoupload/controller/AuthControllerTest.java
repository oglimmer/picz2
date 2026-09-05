/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.*;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.AuthCheckResponse;
import com.oglimmer.photoupload.security.UserContext;
import com.oglimmer.photoupload.service.SessionTokenService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import org.springframework.mock.web.MockHttpServletRequest;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.ResponseEntity;

class AuthControllerTest {

  @Test
  void checkAuthReportsTheAuthenticatedUser() {
    User user = new User();
    user.setEmail("user@example.com");
    user.setEmailVerified(true);
    UserContext userContext = Mockito.mock(UserContext.class);
    Mockito.when(userContext.getCurrentUser()).thenReturn(user);

    AuthController controller = new AuthController(userContext, null);
    ResponseEntity<AuthCheckResponse> resp = controller.checkAuth();
    assertEquals(200, resp.getStatusCode().value());
    AuthCheckResponse body = resp.getBody();
    assertNotNull(body);
    assertEquals(true, body.isSuccess());
    assertEquals("user@example.com", body.getEmail());
    assertTrue(body.isEmailVerified());
    assertFalse(body.isAdmin());
  }

  @Test
  void checkAuthReportsTheAdminFlag() {
    User user = new User();
    user.setEmail("ops@example.com");
    user.setAdmin(true);
    UserContext userContext = Mockito.mock(UserContext.class);
    Mockito.when(userContext.getCurrentUser()).thenReturn(user);

    AuthCheckResponse body = new AuthController(userContext, null).checkAuth().getBody();
    assertNotNull(body);
    assertTrue(body.isAdmin());
  }

  /** D78 — the login answer carries the token plus everything /check would have said. */
  @Test
  void createSessionReturnsTheTokenAndTheAccountFacts() {
    User user = new User();
    user.setEmail("user@example.com");
    user.setEmailVerified(true);
    UserContext userContext = Mockito.mock(UserContext.class);
    Mockito.when(userContext.getCurrentUser()).thenReturn(user);
    SessionTokenService sessions = Mockito.mock(SessionTokenService.class);
    Instant expiresAt = Instant.now().plus(2, ChronoUnit.HOURS);
    Mockito.when(sessions.issue(user))
        .thenReturn(new SessionTokenService.IssuedToken("zst_abc", expiresAt));

    AuthController.SessionResponse body =
        new AuthController(userContext, sessions).createSession().getBody();
    assertNotNull(body);
    assertEquals("zst_abc", body.token());
    assertEquals(expiresAt, body.expiresAt());
    assertTrue(body.expiresInSeconds() > 7000 && body.expiresInSeconds() <= 7200);
    assertEquals("user@example.com", body.email());
    assertTrue(body.emailVerified());
    assertFalse(body.admin());
  }

  @Test
  void endSessionRevokesThePresentedTokenOnly() {
    SessionTokenService sessions = Mockito.mock(SessionTokenService.class);
    AuthController controller = new AuthController(Mockito.mock(UserContext.class), sessions);

    MockHttpServletRequest withToken = new MockHttpServletRequest("DELETE", "/api/auth/sessions/current");
    withToken.addHeader("Authorization", "Bearer zst_live");
    assertEquals(204, controller.endSession(withToken).getStatusCode().value());
    Mockito.verify(sessions).revoke("zst_live");

    // A Basic-authenticated caller has no session to end; that must not blow up.
    MockHttpServletRequest basic = new MockHttpServletRequest("DELETE", "/api/auth/sessions/current");
    basic.addHeader("Authorization", "Basic dXNlcjpwdw==");
    assertEquals(204, controller.endSession(basic).getStatusCode().value());
    Mockito.verifyNoMoreInteractions(sessions);
  }
}
