/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Credentials for Apple Push Notification service, used to tell the iOS app about new photos and
 * newly published albums.
 *
 * <p>The signing key is supplied the same way {@link AppleMapsProperties} takes the MapKit one — as
 * the body of the downloaded {@code AuthKey_XXXX.p8}, injected from a secret. It used to be a
 * classpath filename resolved out of the JAR, which meant the key had to be committed to the repo
 * and baked into every image, and could not be rotated without a rebuild.
 *
 * <p>{@link #isConfigured()} being false is a supported state, not an error: the service then logs
 * once and drops every push, which is the normal state for local dev and for any install without an
 * Apple Developer account.
 */
@Configuration
@ConfigurationProperties(prefix = "app.apns")
@Data
public class ApnsConfig {

  /** Master switch. False skips the client entirely, whatever else is set. */
  private boolean enabled;

  /**
   * PEM body of the {@code .p8} signing key. The preferred source, and the one production uses — it
   * arrives as an env var from a Kubernetes secret, so the key never enters the image.
   */
  private String privateKey = "";

  /**
   * Filesystem path to the {@code .p8}, as a convenience for local development: the key sits
   * gitignored beside the MapKit one and this points at it, which beats pasting a multi-line PEM
   * into a shell. Ignored when {@link #privateKey} is set. Not a classpath name — nothing is read
   * out of the JAR any more.
   */
  private String keyPath = "";

  /** Key ID of the APNs key (10 chars) — the token header's {@code kid}. Not a secret. */
  private String keyId = "";

  /** Apple Developer Team ID (10 chars) — the token's {@code iss}. Not a secret. */
  private String teamId = "";

  /** The app's bundle id, which APNs calls the topic. */
  private String topic = "";

  /** False talks to Apple's sandbox, which is what a debug build of the app registers against. */
  private boolean production;

  /** True when there is both an identity and a key to sign with. */
  public boolean isConfigured() {
    return !teamId.isBlank() && !keyId.isBlank() && (!privateKey.isBlank() || !keyPath.isBlank());
  }
}
