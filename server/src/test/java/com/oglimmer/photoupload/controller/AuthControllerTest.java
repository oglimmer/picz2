/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.*;

import com.oglimmer.photoupload.model.AuthCheckResponse;
import com.oglimmer.photoupload.repository.UserRepository;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.ResponseEntity;

class AuthControllerTest {

  @Test
  void checkAuthParsesEmail() {
    String creds =
        Base64.getEncoder().encodeToString("user@example.com:pw".getBytes(StandardCharsets.UTF_8));
    HttpServletRequest request = Mockito.mock(HttpServletRequest.class);
    Mockito.when(request.getHeader("Authorization")).thenReturn("Basic " + creds);

    UserRepository userRepository = Mockito.mock(UserRepository.class);
    AuthController controller = new AuthController(userRepository);
    ResponseEntity<AuthCheckResponse> resp = controller.checkAuth(request);
    assertEquals(200, resp.getStatusCode().value());
    AuthCheckResponse body = resp.getBody();
    assertNotNull(body);
    assertEquals(true, body.isSuccess());
    assertEquals("user@example.com", body.getEmail());
  }
}
