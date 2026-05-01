/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Phase 5 — TUS resumable uploads. Two flags ride together via Helm:
 *
 * <ul>
 *   <li>{@code enabled} — wires the {@link
 *       com.oglimmer.photoupload.controller.TusHookController} bean and unlocks the {@code
 *       /api/tus/hooks/**} permit in {@link SecurityConfig}.
 *   <li>{@code advertised} — what {@link
 *       com.oglimmer.photoupload.controller.CapabilitiesController} reports to clients. R1
 *       ships {@code enabled=true, advertised=false}; R2 flips advertised.
 * </ul>
 */
@Configuration
@ConfigurationProperties(prefix = "tus")
@Data
public class TusProperties {

  private boolean enabled = false;

  private boolean advertised = false;

  /** Base path tusd serves at (mirrored on the public Ingress). */
  private String endpoint = "/files/";

  /** Per-upload size cap in bytes. Aligned with multipart {@code spring.servlet.multipart.max-file-size}. */
  private long maxSize = 524288000L;

  /**
   * Path-secret embedded in the tusd→api hook URL. The api validates it with constant-time
   * compare; mismatch yields 404 to avoid leaking that the path exists. Cluster-internal only.
   */
  private String hookSecret = "";

  /** TUS protocol version advertised in the capabilities response. */
  private String version = "1.0.0";
}
