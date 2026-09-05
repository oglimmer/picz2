/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.*;

import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.model.AuthCheckResponse;
import com.oglimmer.photoupload.security.UserContext;
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

    AuthController controller = new AuthController(userContext);
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

    AuthCheckResponse body = new AuthController(userContext).checkAuth().getBody();
    assertNotNull(body);
    assertTrue(body.isAdmin());
  }
}
