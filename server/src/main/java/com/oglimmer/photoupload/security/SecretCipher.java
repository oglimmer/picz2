/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.security;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Symmetric encryption for the one secret we have to store and read back: a user's S3 secret access
 * key. Hashing is not an option — the SDK needs the original string to sign requests.
 *
 * <p>AES-256-GCM with a fresh 12-byte IV per value, serialised as {@code v1:base64(iv):base64(ct)}.
 * The version prefix exists so a future key rotation can tell old ciphertext from new without
 * guessing.
 *
 * <p>The key comes from {@code storage.backend-secret-key} (base64, 32 bytes). When it is absent
 * the server still boots and the system default backend keeps working — only creating or using a
 * user-owned backend fails, with a message naming the missing setting rather than a
 * NullPointerException three layers down.
 */
@Component
public class SecretCipher {

  private static final String TRANSFORMATION = "AES/GCM/NoPadding";
  private static final int IV_LENGTH = 12;
  private static final int TAG_LENGTH_BITS = 128;
  private static final String PREFIX = "v1:";

  private final SecretKeySpec key;
  private final SecureRandom random = new SecureRandom();

  public SecretCipher(@Value("${storage.backend-secret-key:}") String base64Key) {
    if (base64Key == null || base64Key.isBlank()) {
      this.key = null;
      return;
    }
    byte[] raw;
    try {
      raw = Base64.getDecoder().decode(base64Key.trim());
    } catch (IllegalArgumentException e) {
      throw new IllegalStateException("storage.backend-secret-key is not valid base64", e);
    }
    if (raw.length != 16 && raw.length != 24 && raw.length != 32) {
      throw new IllegalStateException(
          "storage.backend-secret-key must decode to 16, 24 or 32 bytes, got " + raw.length);
    }
    this.key = new SecretKeySpec(raw, "AES");
  }

  /** True when a key is configured, i.e. user-owned storage backends can be used at all. */
  public boolean isEnabled() {
    return key != null;
  }

  private void requireKey() {
    if (key == null) {
      throw new IllegalStateException(
          "Custom storage backends need storage.backend-secret-key (base64 AES key) to be set");
    }
  }

  public String encrypt(String plaintext) {
    requireKey();
    try {
      byte[] iv = new byte[IV_LENGTH];
      random.nextBytes(iv);
      Cipher cipher = Cipher.getInstance(TRANSFORMATION);
      cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH_BITS, iv));
      byte[] ct = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
      Base64.Encoder enc = Base64.getEncoder();
      return PREFIX + enc.encodeToString(iv) + ":" + enc.encodeToString(ct);
    } catch (GeneralSecurityRuntimeWrapper e) {
      throw e;
    } catch (Exception e) {
      throw new GeneralSecurityRuntimeWrapper("Failed to encrypt storage backend secret", e);
    }
  }

  public String decrypt(String stored) {
    requireKey();
    if (stored == null || !stored.startsWith(PREFIX)) {
      throw new GeneralSecurityRuntimeWrapper(
          "Stored storage backend secret is not in the expected v1 format", null);
    }
    String[] parts = stored.substring(PREFIX.length()).split(":", 2);
    if (parts.length != 2) {
      throw new GeneralSecurityRuntimeWrapper(
          "Stored storage backend secret is not in the expected v1 format", null);
    }
    try {
      Base64.Decoder dec = Base64.getDecoder();
      byte[] iv = dec.decode(parts[0]);
      byte[] ct = dec.decode(parts[1]);
      Cipher cipher = Cipher.getInstance(TRANSFORMATION);
      cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH_BITS, iv));
      return new String(cipher.doFinal(ct), StandardCharsets.UTF_8);
    } catch (Exception e) {
      // A GCM tag mismatch means the key changed (or the row was tampered with). Say so plainly;
      // the recovery is to re-enter the secret, not to retry.
      throw new GeneralSecurityRuntimeWrapper(
          "Cannot decrypt storage backend secret — storage.backend-secret-key may have changed", e);
    }
  }

  /** Unchecked wrapper so callers are not forced to handle six checked JCE exceptions. */
  public static class GeneralSecurityRuntimeWrapper extends RuntimeException {
    public GeneralSecurityRuntimeWrapper(String message, Throwable cause) {
      super(message, cause);
    }
  }
}
