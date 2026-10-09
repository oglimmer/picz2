/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.health.actuate.endpoint.HealthDescriptor;
import org.springframework.boot.health.actuate.endpoint.HealthEndpoint;
import org.springframework.boot.health.contributor.Status;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@Profile(Profiles.API)
@RestController
@RequiredArgsConstructor
public class RootController {

  private final HealthEndpoint healthEndpoint;

  @GetMapping(value = {"/", "/api", "/api/"})
  public HealthDescriptor rootHealth() {
    return healthEndpoint.health();
  }

  /**
   * Public liveness check that works through the Ingress ({@code /actuator} sits on the management
   * port, which the Ingress does not route). Answers 200 while the full actuator health is not DOWN
   * or OUT_OF_SERVICE, 503 otherwise. UNKNOWN (breaker HALF_OPEN) stays 200 so a brief MinIO
   * recovery does not flap an external monitor. The body is the status only: the per-component
   * details stay on the management port.
   */
  @GetMapping("/api/health")
  public ResponseEntity<Map<String, String>> health() {
    return toResponse(healthEndpoint.health().getStatus());
  }

  static ResponseEntity<Map<String, String>> toResponse(Status status) {
    boolean down = Status.DOWN.equals(status) || Status.OUT_OF_SERVICE.equals(status);
    return ResponseEntity.status(down ? 503 : 200).body(Map.of("status", status.getCode()));
  }
}
