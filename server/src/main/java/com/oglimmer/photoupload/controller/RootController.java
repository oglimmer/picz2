/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.health.actuate.endpoint.HealthDescriptor;
import org.springframework.boot.health.actuate.endpoint.HealthEndpoint;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
public class RootController {

  private final HealthEndpoint healthEndpoint;

  @GetMapping(value = {"/", "/api", "/api/"})
  public HealthDescriptor rootHealth() {
    return healthEndpoint.health();
  }
}
