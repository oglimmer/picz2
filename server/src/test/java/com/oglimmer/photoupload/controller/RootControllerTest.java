/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;
import org.springframework.boot.health.contributor.Status;

/** The public {@code /api/health}: 503 when the app is DOWN, 200 otherwise, status code only. */
class RootControllerTest {

  @Test
  void upIs200() {
    var resp = RootController.toResponse(Status.UP);
    assertEquals(200, resp.getStatusCode().value());
    assertEquals("UP", resp.getBody().get("status"));
  }

  @Test
  void unknownStaysAt200SoARecoveringBreakerDoesNotFlap() {
    assertEquals(200, RootController.toResponse(Status.UNKNOWN).getStatusCode().value());
  }

  @Test
  void downIs503() {
    var resp = RootController.toResponse(Status.DOWN);
    assertEquals(503, resp.getStatusCode().value());
    assertEquals("DOWN", resp.getBody().get("status"));
  }

  @Test
  void outOfServiceIs503() {
    assertEquals(503, RootController.toResponse(Status.OUT_OF_SERVICE).getStatusCode().value());
  }
}
