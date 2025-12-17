/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AlbumSubscription;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.model.AlbumSubscriptionRequest;
import com.oglimmer.photoupload.model.AlbumSubscriptionResponse;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.AlbumSubscriptionRepository;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Slf4j
@RequiredArgsConstructor
public class AlbumSubscriptionService {

  private final AlbumSubscriptionRepository subscriptionRepository;
  private final AlbumRepository albumRepository;
  private final EmailService emailService;

  /**
   * Create a new subscription for an album
   *
   * @param shareToken Album share token
   * @param request Subscription request details
   * @return Subscription response
   */
  @Transactional
  public AlbumSubscriptionResponse createSubscription(
      String shareToken, AlbumSubscriptionRequest request) {
    // Find album by share token
    Album album =
        albumRepository
            .findByShareToken(shareToken)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "shareToken", shareToken));

    // Check if subscription already exists
    Optional<AlbumSubscription> existingSubscription =
        subscriptionRepository.findByEmailAndAlbum(request.getEmail(), album);

    if (existingSubscription.isPresent()) {
      AlbumSubscription subscription = existingSubscription.get();

      // Update existing subscription if it exists
      subscription.setNotifyAlbumUpdates(request.getNotifyAlbumUpdates());
      subscription.setNotifyNewAlbums(request.getNotifyNewAlbums());
      subscription.setActive(true);

      // If not confirmed, resend confirmation email
      if (!subscription.getConfirmed()) {
        emailService.sendSubscriptionConfirmationEmail(
            subscription.getEmail(),
            subscription.getConfirmationToken(),
            album.getName(),
            subscription.getUnsubscribeToken());
        return new AlbumSubscriptionResponse(
            "Subscription already exists. Confirmation email resent.");
      }

      subscriptionRepository.save(subscription);
      return mapToResponse(subscription, "Subscription updated successfully.");
    }

    // Create new subscription
    AlbumSubscription subscription = new AlbumSubscription();
    subscription.setEmail(request.getEmail());
    subscription.setAlbum(album);
    subscription.setNotifyAlbumUpdates(request.getNotifyAlbumUpdates());
    subscription.setNotifyNewAlbums(request.getNotifyNewAlbums());
    subscription.setConfirmed(false);
    subscription.setActive(true);

    subscription = subscriptionRepository.save(subscription);

    // Send confirmation email
    emailService.sendSubscriptionConfirmationEmail(
        subscription.getEmail(),
        subscription.getConfirmationToken(),
        album.getName(),
        subscription.getUnsubscribeToken());

    log.info(
        "Subscription created for email: {} on album: {} (id: {})",
        subscription.getEmail(),
        album.getName(),
        album.getId());

    return mapToResponse(subscription, "Subscription created. Please check your email to confirm.");
  }

  /**
   * Confirm a subscription using confirmation token
   *
   * @param confirmationToken Confirmation token
   * @return Subscription response
   */
  @Transactional
  public AlbumSubscriptionResponse confirmSubscription(String confirmationToken) {
    AlbumSubscription subscription =
        subscriptionRepository
            .findByConfirmationToken(confirmationToken)
            .orElseThrow(
                () ->
                    new ResourceNotFoundException(
                        "Subscription", "confirmationToken", confirmationToken));

    if (subscription.getConfirmed()) {
      return mapToResponse(subscription, "Subscription already confirmed.");
    }

    subscription.setConfirmed(true);
    subscriptionRepository.save(subscription);

    log.info(
        "Subscription confirmed for email: {} on album: {}",
        subscription.getEmail(),
        subscription.getAlbum().getName());

    return mapToResponse(subscription, "Subscription confirmed successfully!");
  }

  /**
   * Unsubscribe using unsubscribe token (one-click unsubscribe from email)
   *
   * @param unsubscribeToken Unsubscribe token
   * @return Response message
   */
  @Transactional
  public AlbumSubscriptionResponse unsubscribeByToken(String unsubscribeToken) {
    AlbumSubscription subscription =
        subscriptionRepository
            .findByUnsubscribeToken(unsubscribeToken)
            .orElseThrow(
                () ->
                    new ResourceNotFoundException(
                        "Subscription", "unsubscribeToken", unsubscribeToken));

    subscription.setActive(false);
    subscriptionRepository.save(subscription);

    log.info(
        "Subscription deactivated via token for email: {} on album: {}",
        subscription.getEmail(),
        subscription.getAlbum().getName());

    return new AlbumSubscriptionResponse("Unsubscribed successfully.");
  }

  /**
   * Unsubscribe using email and album share token (legacy method)
   *
   * @param email Subscriber email
   * @param shareToken Album share token
   * @return Response message
   */
  @Transactional
  public AlbumSubscriptionResponse unsubscribe(String email, String shareToken) {
    Album album =
        albumRepository
            .findByShareToken(shareToken)
            .orElseThrow(() -> new ResourceNotFoundException("Album", "shareToken", shareToken));

    AlbumSubscription subscription =
        subscriptionRepository
            .findByEmailAndAlbum(email, album)
            .orElseThrow(
                () ->
                    new ResourceNotFoundException(
                        "Subscription not found for email: "
                            + email
                            + " and album: "
                            + album.getName()));

    subscription.setActive(false);
    subscriptionRepository.save(subscription);

    log.info("Subscription deactivated for email: {} on album: {}", email, album.getName());

    return new AlbumSubscriptionResponse("Unsubscribed successfully.");
  }

  /** Map entity to response DTO */
  private AlbumSubscriptionResponse mapToResponse(AlbumSubscription subscription, String message) {
    AlbumSubscriptionResponse response = new AlbumSubscriptionResponse();
    response.setId(subscription.getId());
    response.setEmail(subscription.getEmail());
    response.setNotifyAlbumUpdates(subscription.getNotifyAlbumUpdates());
    response.setNotifyNewAlbums(subscription.getNotifyNewAlbums());
    response.setConfirmed(subscription.getConfirmed());
    response.setMessage(message);
    return response;
  }
}
