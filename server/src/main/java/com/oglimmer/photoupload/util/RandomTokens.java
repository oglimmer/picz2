/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.util;

import java.security.SecureRandom;
import java.util.HexFormat;

/**
 * The one place that mints opaque random identifiers — share tokens, public asset tokens and the
 * like. One shared {@link SecureRandom}: creating a fresh instance per token, as the callers used
 * to, costs a reseed each time and buys nothing.
 */
public final class RandomTokens {

  private static final SecureRandom RANDOM = new SecureRandom();

  private RandomTokens() {}

  /** {@code byteCount} random bytes as lower-case hex — twice that many characters. */
  public static String hex(int byteCount) {
    byte[] bytes = new byte[byteCount];
    RANDOM.nextBytes(bytes);
    return HexFormat.of().formatHex(bytes);
  }
}
