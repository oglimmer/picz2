/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.security;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Base64;
import org.junit.jupiter.api.Test;

/**
 * The one secret the server has to be able to read back: a user's S3 secret access key. These pin
 * the properties that make that safe to store — no plaintext at rest, no reuse of an IV, and a
 * refusal (not a wrong answer) when the key has changed.
 */
class SecretCipherTest {

  private static String key() {
    byte[] raw = new byte[32];
    for (int i = 0; i < raw.length; i++) {
      raw[i] = (byte) i;
    }
    return Base64.getEncoder().encodeToString(raw);
  }

  private static String otherKey() {
    byte[] raw = new byte[32];
    for (int i = 0; i < raw.length; i++) {
      raw[i] = (byte) (100 + i);
    }
    return Base64.getEncoder().encodeToString(raw);
  }

  @Test
  void roundTripsAValue() {
    SecretCipher cipher = new SecretCipher(key());
    String secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";

    String stored = cipher.encrypt(secret);

    assertNotEquals(secret, stored);
    assertFalse(stored.contains(secret));
    assertEquals(secret, cipher.decrypt(stored));
  }

  @Test
  void encryptingTwiceProducesDifferentCiphertext() {
    SecretCipher cipher = new SecretCipher(key());

    String first = cipher.encrypt("same-secret");
    String second = cipher.encrypt("same-secret");

    // A fresh IV per value. Equal ciphertext would leak that two users share a key.
    assertNotEquals(first, second);
    assertEquals("same-secret", cipher.decrypt(first));
    assertEquals("same-secret", cipher.decrypt(second));
  }

  @Test
  void aChangedKeyFailsLoudlyRatherThanReturningGarbage() {
    String stored = new SecretCipher(key()).encrypt("secret");

    SecretCipher rotated = new SecretCipher(otherKey());

    assertThrows(SecretCipher.GeneralSecurityRuntimeWrapper.class, () -> rotated.decrypt(stored));
  }

  @Test
  void withoutAKeyTheFeatureIsOffRatherThanBroken() {
    SecretCipher cipher = new SecretCipher("");

    assertFalse(cipher.isEnabled());
    // The message has to name the setting: this surfaces to an operator, not a developer.
    IllegalStateException e =
        assertThrows(IllegalStateException.class, () -> cipher.encrypt("secret"));
    assertTrue(e.getMessage().contains("storage.backend-secret-key"));
  }

  @Test
  void aKeyOfTheWrongLengthIsRejectedAtStartup() {
    String tooShort = Base64.getEncoder().encodeToString(new byte[7]);

    assertThrows(IllegalStateException.class, () -> new SecretCipher(tooShort));
  }

  @Test
  void garbageInTheColumnIsRejected() {
    SecretCipher cipher = new SecretCipher(key());

    assertThrows(
        SecretCipher.GeneralSecurityRuntimeWrapper.class, () -> cipher.decrypt("not-encrypted"));
  }
}
