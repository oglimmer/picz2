/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.oglimmer.photoupload.config.AppleMapsProperties;
import com.oglimmer.photoupload.config.Profiles;
import jakarta.annotation.PostConstruct;
import java.security.KeyFactory;
import java.security.interfaces.ECPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Mints the ES256 JWT that MapKit JS needs before it will draw a map.
 *
 * <p>The signing key never leaves the server — the browser only ever sees a short-lived token,
 * which is the whole point of Apple's design. Tokens are cached and re-minted shortly before they
 * expire rather than per request: every gallery visitor asks for one, and a public album can have
 * many at once.
 *
 * <p>Runs on the api profile only; the worker has no HTTP surface that needs it.
 */
@Service
@Profile(Profiles.API)
@Slf4j
@RequiredArgsConstructor
public class AppleMapsTokenService {

  /** Re-mint this long before expiry so a token handed out now is still valid on arrival. */
  private static final long REFRESH_MARGIN_SECONDS = 60;

  private final AppleMapsProperties properties;

  private ECPrivateKey signingKey;
  private volatile String cachedToken;
  private volatile Instant cachedUntil = Instant.EPOCH;

  /**
   * Parses the configured key once at startup so a malformed {@code .p8} is a boot-time log line
   * rather than a mystery 500 the first time somebody opens the map. A parse failure disables the
   * feature instead of failing the boot — the rest of the gallery does not depend on it.
   */
  @PostConstruct
  void loadKey() {
    if (!properties.isConfigured()) {
      log.info("🗺️ Apple Maps not configured (maps.apple.*) — map filter will be hidden");
      return;
    }
    try {
      String pem =
          properties
              .getPrivateKey()
              .replace("-----BEGIN PRIVATE KEY-----", "")
              .replace("-----END PRIVATE KEY-----", "")
              .replaceAll("\\s", "");
      byte[] der = Base64.getDecoder().decode(pem);
      signingKey =
          (ECPrivateKey) KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(der));
      log.info("🗺️ Apple Maps signing key loaded (keyId={})", properties.getKeyId());
    } catch (Exception e) {
      signingKey = null;
      log.error(
          "🗺️ Apple Maps private key could not be parsed — map filter stays hidden: {}",
          e.getMessage());
    }
  }

  /** True once a usable key is loaded. Drives the {@code /api/capabilities} maps flag. */
  public boolean isEnabled() {
    return signingKey != null;
  }

  /**
   * Returns a valid MapKit JS token, minting a new one when the cached token is gone or close to
   * expiring.
   *
   * @throws IllegalStateException if Apple Maps is not configured — callers should check {@link
   *     #isEnabled()} first
   */
  public String token() {
    if (signingKey == null) {
      throw new IllegalStateException("Apple Maps is not configured");
    }
    String current = cachedToken;
    if (current != null && Instant.now().isBefore(cachedUntil)) {
      return current;
    }
    synchronized (this) {
      // Re-check: a second thread may have minted while this one waited on the lock.
      if (cachedToken != null && Instant.now().isBefore(cachedUntil)) {
        return cachedToken;
      }
      Instant now = Instant.now();
      Instant expiry = now.plusSeconds(properties.getTtlSeconds());
      cachedToken = mint(now, expiry);
      cachedUntil = expiry.minusSeconds(REFRESH_MARGIN_SECONDS);
      return cachedToken;
    }
  }

  private String mint(Instant issuedAt, Instant expiry) {
    try {
      JWTClaimsSet.Builder claims =
          new JWTClaimsSet.Builder()
              .issuer(properties.getTeamId())
              .issueTime(Date.from(issuedAt))
              .expirationTime(Date.from(expiry));
      if (!properties.getOrigin().isBlank()) {
        // Apple rejects the token when the page's origin does not match this claim, which is what
        // stops a copied token from being usable on someone else's site.
        claims.claim("origin", properties.getOrigin());
      }
      SignedJWT jwt =
          new SignedJWT(
              new JWSHeader.Builder(JWSAlgorithm.ES256)
                  .keyID(properties.getKeyId())
                  .type(JOSEObjectType.JWT)
                  .build(),
              claims.build());
      jwt.sign(new ECDSASigner(signingKey));
      return jwt.serialize();
    } catch (Exception e) {
      throw new IllegalStateException("Could not sign MapKit JS token", e);
    }
  }
}
