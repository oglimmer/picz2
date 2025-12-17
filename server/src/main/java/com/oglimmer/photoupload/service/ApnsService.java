/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.eatthepath.pushy.apns.ApnsClient;
import com.eatthepath.pushy.apns.ApnsClientBuilder;
import com.eatthepath.pushy.apns.auth.ApnsSigningKey;
import com.eatthepath.pushy.apns.util.ApnsPayloadBuilder;
import com.eatthepath.pushy.apns.util.SimpleApnsPayloadBuilder;
import com.eatthepath.pushy.apns.util.SimpleApnsPushNotification;
import com.oglimmer.photoupload.config.ApnsConfig;
import com.oglimmer.photoupload.entity.DeviceToken;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
@Slf4j
public class ApnsService {

  private final ApnsConfig apnsConfig;
  private final DeviceTokenService deviceTokenService;

  private ApnsClient apnsClient;

  @PostConstruct
  public void init() {
    if (!apnsConfig.isEnabled()) {
      log.info("APNs is disabled");
      return;
    }

    try {
      File p8File = getKeyFile(apnsConfig.getKeyPath());
      ApnsClient client =
          new ApnsClientBuilder()
              .setApnsServer(
                  apnsConfig.isProduction()
                      ? ApnsClientBuilder.PRODUCTION_APNS_HOST
                      : ApnsClientBuilder.DEVELOPMENT_APNS_HOST)
              .setSigningKey(
                  ApnsSigningKey.loadFromPkcs8File(
                      p8File, apnsConfig.getTeamId(), apnsConfig.getKeyId()))
              .build();

      this.apnsClient = client;
      log.info(
          "APNs client initialized for {} environment",
          apnsConfig.isProduction() ? "PRODUCTION" : "DEVELOPMENT");
    } catch (Exception e) {
      log.error("Failed to initialize APNs client", e);
    }
  }

  private File getKeyFile(String keyPath) throws IOException {
    File file = new File(keyPath);

    // If it's an absolute path and exists, use it directly
    if (file.isAbsolute() && file.exists()) {
      return file;
    }

    // Otherwise, try to load from classpath
    Resource resource = new ClassPathResource(keyPath);
    if (resource.exists()) {
      // For classpath resources in JAR files, we need to copy to a temp file
      if (!resource.isFile()) {
        Path tempFile = Files.createTempFile("apns-key-", ".p8");
        Files.copy(
            resource.getInputStream(), tempFile, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        tempFile.toFile().deleteOnExit();
        return tempFile.toFile();
      }
      return resource.getFile();
    }

    // If not found anywhere, throw exception
    throw new IOException("APNs key file not found: " + keyPath);
  }

  @PreDestroy
  public void cleanup() {
    if (apnsClient != null) {
      apnsClient.close();
    }
  }

  public void sendAlbumUpdateNotification(
      String email, String albumName, String shareToken, int newImageCount) {
    if (!apnsConfig.isEnabled() || apnsClient == null) {
      log.debug("APNs disabled, skipping push notification");
      return;
    }

    List<DeviceToken> tokens = deviceTokenService.getActiveTokensByEmail(email);
    if (tokens.isEmpty()) {
      log.debug("No active device tokens for email: {}", email);
      return;
    }

    String title = "New Photos Added";
    String body =
        String.format(
            "%d new photo%s added to \"%s\"",
            newImageCount, newImageCount > 1 ? "s" : "", albumName);

    ApnsPayloadBuilder builder =
        new SimpleApnsPayloadBuilder()
            .setAlertTitle(title)
            .setAlertBody(body)
            .setSound("default")
            .setBadgeNumber(1)
            .addCustomProperty("albumShareToken", shareToken)
            .addCustomProperty("notificationType", "albumUpdate");

    sendToDevices(tokens, builder.build());
  }

  public void sendNewAlbumNotification(
      String email, String ownerName, String albumName, String shareToken) {
    if (!apnsConfig.isEnabled() || apnsClient == null) {
      log.debug("APNs disabled, skipping push notification");
      return;
    }

    List<DeviceToken> tokens = deviceTokenService.getActiveTokensByEmail(email);
    if (tokens.isEmpty()) {
      log.debug("No active device tokens for email: {}", email);
      return;
    }

    String title = "New Album Available";
    String body = String.format("%s created a new album: \"%s\"", ownerName, albumName);

    ApnsPayloadBuilder builder =
        new SimpleApnsPayloadBuilder()
            .setAlertTitle(title)
            .setAlertBody(body)
            .setSound("default")
            .setBadgeNumber(1)
            .addCustomProperty("albumShareToken", shareToken)
            .addCustomProperty("notificationType", "newAlbum");

    sendToDevices(tokens, builder.build());
  }

  private void sendToDevices(List<DeviceToken> tokens, String payload) {
    for (DeviceToken token : tokens) {
      SimpleApnsPushNotification notification =
          new SimpleApnsPushNotification(token.getDeviceToken(), apnsConfig.getTopic(), payload);

      apnsClient
          .sendNotification(notification)
          .whenComplete(
              (response, cause) -> {
                if (cause != null) {
                  log.error("Failed to send push to device {}", token.getDeviceToken(), cause);
                  deviceTokenService.recordFailure(token.getDeviceToken(), cause.getMessage());
                } else {
                  if (response.isAccepted()) {
                    log.debug("Push notification sent successfully to {}", token.getDeviceToken());
                  } else {
                    String rejection = response.getRejectionReason().orElse("Unknown");
                    log.warn(
                        "Push notification rejected for {}: {}", token.getDeviceToken(), rejection);

                    // Handle specific APNs error codes
                    if ("BadDeviceToken".equals(rejection) || "Unregistered".equals(rejection)) {
                      deviceTokenService.recordFailure(token.getDeviceToken(), rejection);
                    }
                  }
                }
              });
    }
  }
}
