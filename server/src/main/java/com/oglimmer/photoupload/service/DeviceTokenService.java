/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.DeviceToken;
import com.oglimmer.photoupload.model.DeviceTokenRequest;
import com.oglimmer.photoupload.repository.DeviceTokenRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Slf4j
public class DeviceTokenService {

  private final DeviceTokenRepository deviceTokenRepository;

  @Transactional
  public DeviceToken registerOrUpdateToken(DeviceTokenRequest request) {
    Optional<DeviceToken> existing =
        deviceTokenRepository.findByDeviceToken(request.getDeviceToken());

    if (existing.isPresent()) {
      DeviceToken token = existing.get();
      token.setEmail(request.getEmail());
      token.setAppVersion(request.getAppVersion());
      token.setDeviceModel(request.getDeviceModel());
      token.setOsVersion(request.getOsVersion());
      token.setLastActiveAt(Instant.now());
      token.setIsActive(true);
      token.setFailureCount(0); // Reset on re-registration
      log.info("Updated existing device token for email: {}", request.getEmail());
      return deviceTokenRepository.save(token);
    }

    DeviceToken newToken = new DeviceToken();
    newToken.setDeviceToken(request.getDeviceToken());
    newToken.setEmail(request.getEmail());
    newToken.setPlatform("ios");
    newToken.setAppVersion(request.getAppVersion());
    newToken.setDeviceModel(request.getDeviceModel());
    newToken.setOsVersion(request.getOsVersion());
    log.info("Registered new device token for email: {}", request.getEmail());
    return deviceTokenRepository.save(newToken);
  }

  @Transactional
  public void deactivateToken(String deviceToken) {
    deviceTokenRepository
        .findByDeviceToken(deviceToken)
        .ifPresent(
            token -> {
              token.setIsActive(false);
              deviceTokenRepository.save(token);
              log.info("Deactivated device token: {}", deviceToken);
            });
  }

  public List<DeviceToken> getActiveTokensByEmail(String email) {
    return deviceTokenRepository.findByEmailAndIsActiveTrue(email);
  }

  @Transactional
  public void recordFailure(String deviceToken, String reason) {
    deviceTokenRepository
        .findByDeviceToken(deviceToken)
        .ifPresent(
            token -> {
              token.setFailureCount(token.getFailureCount() + 1);
              token.setLastFailureReason(reason);
              if (token.getFailureCount() >= 3) {
                token.setIsActive(false);
                log.warn(
                    "Deactivated device token {} after {} failures",
                    deviceToken,
                    token.getFailureCount());
              }
              deviceTokenRepository.save(token);
            });
  }

  @Scheduled(cron = "0 0 2 * * *") // Run at 2 AM daily
  @Transactional
  public void cleanupFailedTokens() {
    int deactivated = deviceTokenRepository.deactivateFailedTokens(3);
    log.info("Cleanup: Deactivated {} device tokens with 3+ failures", deactivated);
  }
}
