/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import static org.junit.jupiter.api.Assertions.*;

import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;

class SecurityConfigTest {

  @Test
  void passwordEncoderIsBCrypt() {
    SecurityConfig cfg = new SecurityConfig(null);
    PasswordEncoder enc = cfg.passwordEncoder();
    String encoded = enc.encode("pw");
    // BCrypt encodes to a hash, not plaintext
    assertNotEquals("pw", encoded);
    // BCrypt encoded strings start with $2a$ or similar
    assertTrue(encoded.startsWith("$2"));
    // Verify the encoder can match the original password
    assertTrue(enc.matches("pw", encoded));
  }

  /**
   * The 401 must not carry a challenge the browser recognises. With Spring's default {@code Basic}
   * challenge, Chrome pops its native credentials dialog for any 401 — including one answering a
   * background {@code fetch()} — which is how a stale saved password produced a login prompt on a
   * public share link.
   */
  @Test
  void unauthorizedChallengeDoesNotPromptTheBrowser() throws Exception {
    SecurityConfig cfg = new SecurityConfig(null);
    MockHttpServletResponse response = new MockHttpServletResponse();

    cfg.silentBasicEntryPoint()
        .commence(
            new MockHttpServletRequest("GET", "/api/auth/check"),
            response,
            new BadCredentialsException("bad credentials"));

    assertEquals(HttpServletResponse.SC_UNAUTHORIZED, response.getStatus());

    String challenge = response.getHeader("WWW-Authenticate");
    // RFC 7235 wants a challenge on a 401, so one is sent — just not in a scheme any browser acts
    // on. Anything starting with "Basic" would bring the dialog straight back.
    assertNotNull(challenge);
    assertFalse(challenge.regionMatches(true, 0, "Basic", 0, "Basic".length()));
  }
}
