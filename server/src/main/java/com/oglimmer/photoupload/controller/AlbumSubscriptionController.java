/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.controller;

import com.oglimmer.photoupload.model.AlbumSubscriptionRequest;
import com.oglimmer.photoupload.model.AlbumSubscriptionResponse;
import com.oglimmer.photoupload.service.AlbumSubscriptionService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** REST controller for managing album subscriptions (public access) */
@RestController
@RequestMapping("/api/public/subscriptions")
@Slf4j
@RequiredArgsConstructor
public class AlbumSubscriptionController {

  private final AlbumSubscriptionService subscriptionService;

  /**
   * Subscribe to album updates
   *
   * @param shareToken Album share token
   * @param request Subscription details
   * @return Subscription response
   */
  @PostMapping("/albums/{shareToken}")
  public ResponseEntity<AlbumSubscriptionResponse> subscribeToAlbum(
      @PathVariable String shareToken, @Valid @RequestBody AlbumSubscriptionRequest request) {

    log.info(
        "Subscription request received for album: {} from email: {}",
        shareToken,
        request.getEmail());

    AlbumSubscriptionResponse response =
        subscriptionService.createSubscription(shareToken, request);

    return ResponseEntity.ok(response);
  }

  /**
   * Confirm subscription via email token
   *
   * @param token Confirmation token
   * @return Confirmation response
   */
  @GetMapping("/confirm")
  public ResponseEntity<AlbumSubscriptionResponse> confirmSubscription(@RequestParam String token) {

    log.info("Subscription confirmation request received for token: {}", token);

    AlbumSubscriptionResponse response = subscriptionService.confirmSubscription(token);

    return ResponseEntity.ok(response);
  }

  /**
   * Unsubscribe from album updates using unsubscribe token (one-click unsubscribe from email)
   *
   * @param token Unsubscribe token
   * @return Unsubscribe response
   */
  @GetMapping("/unsubscribe")
  public ResponseEntity<AlbumSubscriptionResponse> unsubscribeByToken(@RequestParam String token) {

    log.info("Unsubscribe request received for token: {}", token);

    AlbumSubscriptionResponse response = subscriptionService.unsubscribeByToken(token);

    return ResponseEntity.ok(response);
  }

  /**
   * Unsubscribe from album updates (legacy method using email and shareToken)
   *
   * @param email Subscriber email
   * @param shareToken Album share token
   * @return Unsubscribe response
   */
  @PostMapping("/unsubscribe")
  public ResponseEntity<AlbumSubscriptionResponse> unsubscribe(
      @RequestParam String email, @RequestParam String shareToken) {

    log.info("Unsubscribe request received for email: {} on album: {}", email, shareToken);

    AlbumSubscriptionResponse response = subscriptionService.unsubscribe(email, shareToken);

    return ResponseEntity.ok(response);
  }
}
