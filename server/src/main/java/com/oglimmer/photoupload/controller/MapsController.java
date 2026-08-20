/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.service.AppleMapsTokenService;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Hands MapKit JS the token it needs to initialise.
 *
 * <p>Unauthenticated on purpose: public share links show the map too, so their visitors must be
 * able to fetch a token. The token grants nothing but map tiles for this install's Apple Developer
 * account, is short-lived, and — when {@code maps.apple.origin} is set — only works on our own
 * origin.
 *
 * <p>Returns the bare JWT as {@code text/plain}, which is exactly what MapKit's authorization
 * callback expects.
 */
@Profile(Profiles.API)
@RestController
@RequiredArgsConstructor
public class MapsController {

  private final AppleMapsTokenService tokenService;

  @GetMapping(value = "/api/maps/token", produces = MediaType.TEXT_PLAIN_VALUE)
  public ResponseEntity<String> token() {
    if (!tokenService.isEnabled()) {
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
          .body("Apple Maps is not configured");
    }
    return ResponseEntity.ok()
        // Never cached by proxies: tokens expire, and a stale one breaks the map silently.
        .cacheControl(CacheControl.noStore())
        .body(tokenService.token());
  }
}
