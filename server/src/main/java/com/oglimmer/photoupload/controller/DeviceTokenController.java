/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.DeviceToken;
import com.oglimmer.photoupload.model.DeviceTokenRequest;
import com.oglimmer.photoupload.model.DeviceTokenResponse;
import com.oglimmer.photoupload.service.DeviceTokenService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Profile(Profiles.API)
@RestController
@RequestMapping("/api/device-tokens")
@RequiredArgsConstructor
@Slf4j
public class DeviceTokenController {

  private final DeviceTokenService deviceTokenService;

  @PostMapping
  public ResponseEntity<DeviceTokenResponse> registerToken(
      @Valid @RequestBody DeviceTokenRequest request) {
    DeviceToken token = deviceTokenService.registerOrUpdateToken(request);
    return ResponseEntity.ok(mapToResponse(token));
  }

  @DeleteMapping
  public ResponseEntity<Void> unregisterToken(@RequestParam String deviceToken) {
    deviceTokenService.deactivateToken(deviceToken);
    return ResponseEntity.noContent().build();
  }

  private DeviceTokenResponse mapToResponse(DeviceToken token) {
    DeviceTokenResponse response = new DeviceTokenResponse();
    response.setId(token.getId());
    response.setDeviceToken(token.getDeviceToken());
    response.setEmail(token.getEmail());
    response.setIsActive(token.getIsActive());
    response.setCreatedAt(token.getCreatedAt());
    return response;
  }
}
