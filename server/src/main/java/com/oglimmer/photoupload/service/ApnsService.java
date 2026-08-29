/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.eatthepath.pushy.apns.ApnsClient;
import com.eatthepath.pushy.apns.ApnsClientBuilder;
import com.eatthepath.pushy.apns.auth.ApnsSigningKey;
import com.eatthepath.pushy.apns.util.ApnsPayloadBuilder;
import com.eatthepath.pushy.apns.util.SimpleApnsPayloadBuilder;
import com.eatthepath.pushy.apns.util.SimpleApnsPushNotification;
import com.oglimmer.photoupload.config.ApnsConfig;
import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.DeviceToken;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

@Profile(Profiles.API)
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

    if (!apnsConfig.isConfigured()) {
      log.info(
          "APNs not configured (app.apns.private-key / key-path, key-id, team-id) — "
              + "push notifications will be skipped");
      return;
    }

    try {
      ApnsClient client =
          new ApnsClientBuilder()
              .setApnsServer(
                  apnsConfig.isProduction()
                      ? ApnsClientBuilder.PRODUCTION_APNS_HOST
                      : ApnsClientBuilder.DEVELOPMENT_APNS_HOST)
              .setSigningKey(loadSigningKey())
              .build();

      this.apnsClient = client;
      log.info(
          "APNs client initialized for {} environment (keyId={})",
          apnsConfig.isProduction() ? "PRODUCTION" : "DEVELOPMENT",
          apnsConfig.getKeyId());
    } catch (Exception e) {
      // A bad key disables push, it does not stop the pod: nothing else in the api depends on it,
      // and a boot loop over a notification channel would take the whole gallery down with it.
      log.error("Failed to initialize APNs client — push notifications are off", e);
    }
  }

  /**
   * The signing key, from the secret if there is one, else from a file on disk.
   *
   * <p>The PEM body wins because that is how production supplies it — an env var out of a
   * Kubernetes secret, so the key never enters the image and can be rotated without a rebuild.
   * {@code key-path} exists for local development, where the {@code .p8} sits gitignored beside the
   * MapKit key. Nothing is read from the classpath any more; the key is no longer in the JAR.
   */
  private ApnsSigningKey loadSigningKey() throws Exception {
    String pem = apnsConfig.getPrivateKey();
    if (!pem.isBlank()) {
      try (InputStream in = new ByteArrayInputStream(pem.getBytes(StandardCharsets.UTF_8))) {
        return ApnsSigningKey.loadFromInputStream(
            in, apnsConfig.getTeamId(), apnsConfig.getKeyId());
      }
    }

    File file = new File(apnsConfig.getKeyPath());
    if (!file.isFile()) {
      throw new IOException("APNs key file not found: " + apnsConfig.getKeyPath());
    }
    return ApnsSigningKey.loadFromPkcs8File(file, apnsConfig.getTeamId(), apnsConfig.getKeyId());
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
