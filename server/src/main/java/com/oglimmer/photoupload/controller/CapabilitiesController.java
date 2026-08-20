/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.config.TusProperties;
import com.oglimmer.photoupload.service.AppleMapsTokenService;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * What ingest paths the server supports today. Clients (iOS / web) cache this and pick TUS or
 * multipart based on what's advertised here. Phase 5d/R1 ships {@code tus.advertised=false} even
 * though the tusd Deployment is live; R2 flips advertised to switch clients over.
 */
@Profile(Profiles.API)
@RestController
@RequiredArgsConstructor
public class CapabilitiesController {

  private final TusProperties tusProperties;
  private final AppleMapsTokenService appleMapsTokenService;

  @GetMapping("/api/capabilities")
  public Capabilities get() {
    return new Capabilities(
        new TusCapability(
            tusProperties.isAdvertised(),
            tusProperties.getEndpoint(),
            tusProperties.getVersion(),
            tusProperties.getMaxSize()),
        new MultipartCapability(true, "/api/upload"),
        new MapsCapability(appleMapsTokenService.isEnabled()));
  }

  public record Capabilities(
      TusCapability tus, MultipartCapability multipart, MapsCapability maps) {}

  public record TusCapability(boolean enabled, String endpoint, String version, long maxSize) {}

  public record MultipartCapability(boolean enabled, String endpoint) {}

  /**
   * Whether the gallery's map filter can work. False when {@code maps.apple.*} is unset or the
   * private key failed to parse — the UI then hides the filter rather than offering a map that
   * would never load.
   */
  public record MapsCapability(boolean enabled) {}
}
