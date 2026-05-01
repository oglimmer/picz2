/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.config.TusProperties;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * What ingest paths the server supports today. Clients (iOS / web) cache this and pick TUS or
 * multipart based on what's advertised here. Phase 5d/R1 ships {@code tus.advertised=false}
 * even though the tusd Deployment is live; R2 flips advertised to switch clients over.
 */
@Profile(Profiles.API)
@RestController
@RequiredArgsConstructor
public class CapabilitiesController {

  private final TusProperties tusProperties;

  @GetMapping("/api/capabilities")
  public Capabilities get() {
    return new Capabilities(
        new TusCapability(
            tusProperties.isAdvertised(),
            tusProperties.getEndpoint(),
            tusProperties.getVersion(),
            tusProperties.getMaxSize()),
        new MultipartCapability(true, "/api/upload"));
  }

  public record Capabilities(TusCapability tus, MultipartCapability multipart) {}

  public record TusCapability(boolean enabled, String endpoint, String version, long maxSize) {}

  public record MultipartCapability(boolean enabled, String endpoint) {}
}
