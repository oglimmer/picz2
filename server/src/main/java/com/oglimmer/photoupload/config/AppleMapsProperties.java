/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Credentials for MapKit JS, used by the gallery's map filter.
 *
 * <p>MapKit JS refuses to initialise without a short-lived ES256 JWT signed by an Apple Developer
 * "MapKit JS" private key. The three ids below come from the Apple Developer portal; the key itself
 * is the body of the downloaded {@code AuthKey_XXXX.p8} file.
 *
 * <p>All fields are empty by default, and {@link #isConfigured()} being false is a supported state,
 * not an error: the server then advertises the map capability as disabled and the UI hides the
 * filter entirely. That keeps local dev and any install without an Apple account working.
 */
@Configuration
@ConfigurationProperties(prefix = "maps.apple")
@Data
public class AppleMapsProperties {

  /** Apple Developer Team ID (10 chars) — becomes the token's {@code iss}. */
  private String teamId = "";

  /** Key ID of the MapKit JS key (10 chars) — becomes the token header's {@code kid}. */
  private String keyId = "";

  /**
   * PEM body of the {@code .p8} private key. Accepted with or without the {@code -----BEGIN PRIVATE
   * KEY-----} armour and with any line wrapping, because secret managers mangle both.
   */
  private String privateKey = "";

  /**
   * Web origin the token is restricted to, e.g. {@code https://photos.example.com}. Optional but
   * strongly recommended: without it a leaked token works from any site. Leave blank to omit the
   * claim.
   */
  private String origin = "";

  /**
   * Token lifetime in seconds. Apple caps MapKit JS tokens at 7 days; short is better because the
   * page simply asks for a new one. 30 minutes covers a long browsing session with one fetch.
   */
  private long ttlSeconds = 1800;

  public boolean isConfigured() {
    return !teamId.isBlank() && !keyId.isBlank() && !privateKey.isBlank();
  }
}
