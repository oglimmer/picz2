/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;
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
}
