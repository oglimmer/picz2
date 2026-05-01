/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.config.TusProperties;
import com.oglimmer.photoupload.model.tus.TusHookRequest;
import com.oglimmer.photoupload.model.tus.TusHookResponse;
import com.oglimmer.photoupload.service.TusHookService;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Phase 5 — receives tusd HTTP hook callbacks. The tusd Deployment POSTs to {@code
 * /api/tus/hooks/{secret}} where {@code secret} is the shared {@code tus.hook-secret} (D27).
 *
 * <p>Every successful response is HTTP 200 with a {@link TusHookResponse} JSON body; tusd
 * decodes the body and uses its {@code HTTPResponse.StatusCode} to decide what to surface to
 * the client. Returning non-2xx (or an empty body) would make tusd log "failed to parse hook
 * response" and propagate 500 to the client — see {@link TusHookResponse} for the schema.
 *
 * <p>Path-secret mismatch is the one case where we *don't* return a hook-shaped JSON: a probe
 * with the wrong secret gets the same 404 an unmapped URL would yield, so the path's existence
 * isn't observable. tusd itself never calls with a wrong secret because the secret is a config
 * value, not user input.
 */
@Profile(Profiles.API)
@RestController
@RequestMapping("/api/tus/hooks")
@ConditionalOnProperty(prefix = "tus", name = "enabled", havingValue = "true")
@RequiredArgsConstructor
@Slf4j
public class TusHookController {

  private final TusProperties properties;
  private final TusHookService hookService;

  @PostMapping("/{secret}")
  public ResponseEntity<?> handle(
      @PathVariable("secret") String secret, @RequestBody TusHookRequest request) {
    if (!constantTimeEquals(secret, properties.getHookSecret())) {
      return ResponseEntity.notFound().build();
    }
    if (request == null || request.type() == null) {
      log.warn("TUS hook payload missing Type");
      // Bad payload — surface a hook-shaped reject so tusd can parse our response and surface
      // 400 to the client. (Should never happen in normal operation; tusd always sends Type.)
      return ResponseEntity.ok(TusHookResponse.reject(400, "missing-type"));
    }
    TusHookResponse response =
        switch (request.type()) {
          case "pre-create" -> hookService.handlePreCreate(request);
          case "post-finish" -> hookService.handlePostFinish(request);
          case "post-terminate" -> hookService.handlePostTerminate(request);
          default -> {
            log.debug("Ignoring TUS hook type: {}", request.type());
            yield TusHookResponse.allow();
          }
        };
    return ResponseEntity.ok(response);
  }

  /**
   * Constant-time equality. Standard {@link String#equals} short-circuits on the first
   * differing byte, leaking position information through timing — irrelevant for cluster-internal
   * use today, but cheap insurance against future deploy mistakes that put the path on a public
   * Ingress.
   */
  private static boolean constantTimeEquals(String a, String b) {
    if (a == null || b == null) {
      return false;
    }
    byte[] ba = a.getBytes(StandardCharsets.UTF_8);
    byte[] bb = b.getBytes(StandardCharsets.UTF_8);
    return MessageDigest.isEqual(ba, bb);
  }
}
