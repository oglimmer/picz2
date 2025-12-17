/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AlbumSubscription;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.AlbumSubscriptionRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import java.time.Instant;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Service for processing album subscription notifications on a schedule */
@Service
@Slf4j
@RequiredArgsConstructor
public class AlbumSubscriptionNotificationService {

  private final AlbumSubscriptionRepository subscriptionRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final AlbumRepository albumRepository;
  private final EmailService emailService;
  private final ApnsService apnsService;

  /** Process all subscriptions and send notifications for updates. Runs every 6 hours. */
  // @Scheduled(cron = "0 0 */6 * * *") // Run at minute 0 of every 6th hour
  @Scheduled(cron = "0 * * * * *") // Run at minute 0 of every 6th hour
  @Transactional
  public void processSubscriptionNotifications() {
    log.info("Starting subscription notification processing");

    List<AlbumSubscription> subscriptions = subscriptionRepository.findAllActiveAndConfirmed();

    log.info("Found {} active and confirmed subscriptions to process", subscriptions.size());

    int albumUpdatesSent = 0;
    int newAlbumsSent = 0;

    for (AlbumSubscription subscription : subscriptions) {
      try {
        boolean notificationSent = false;

        // Check for album updates (new images)
        if (subscription.getNotifyAlbumUpdates()) {
          if (checkAndNotifyAlbumUpdates(subscription)) {
            albumUpdatesSent++;
            notificationSent = true;
          }
        }

        // Check for new albums from the owner
        if (subscription.getNotifyNewAlbums()) {
          if (checkAndNotifyNewAlbums(subscription)) {
            newAlbumsSent++;
            notificationSent = true;
          }
        }

        // Update last notified timestamp if any notification was sent
        if (notificationSent) {
          subscription.setLastNotifiedAt(Instant.now());
          subscriptionRepository.save(subscription);
        }

      } catch (Exception e) {
        log.error(
            "Error processing subscription {} for email {}",
            subscription.getId(),
            subscription.getEmail(),
            e);
        // Continue processing other subscriptions
      }
    }

    log.info(
        "Subscription notification processing complete. Album updates sent: {}, New albums sent: {}",
        albumUpdatesSent,
        newAlbumsSent);
  }

  /**
   * Check if album has new images and send notification if needed. This method respects the
   * tag-based visibility rules: - If no images have tags: all images are visible - If at least one
   * image has a tag: only images WITH tags are visible
   *
   * @param subscription The subscription to check
   * @return true if notification was sent
   */
  private boolean checkAndNotifyAlbumUpdates(AlbumSubscription subscription) {
    Album album = subscription.getAlbum();
    Instant lastNotified = subscription.getLastNotifiedAt();

    // If never notified, use subscription creation time
    if (lastNotified == null) {
      lastNotified = subscription.getCreatedAt();
    }

    // Get all files in the album
    List<FileMetadata> allFiles =
        fileMetadataRepository.findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(
            album.getShareToken());

    // Calculate visible image count at the time of last notification
    int visibleCountBefore = countVisibleImages(allFiles, lastNotified);

    // Calculate current visible image count
    int visibleCountNow = countVisibleImages(allFiles, null);

    // Only notify if visible count has increased
    int newVisibleImages = visibleCountNow - visibleCountBefore;

    if (newVisibleImages > 0) {
      log.info(
          "Found {} new visible images in album {} for subscription {} (was: {}, now: {})",
          newVisibleImages,
          album.getName(),
          subscription.getId(),
          visibleCountBefore,
          visibleCountNow);

      emailService.sendAlbumUpdateNotification(
          subscription.getEmail(),
          album.getName(),
          album.getShareToken(),
          newVisibleImages,
          subscription.getUnsubscribeToken());

      // Send push notification
      apnsService.sendAlbumUpdateNotification(
          subscription.getEmail(), album.getName(), album.getShareToken(), newVisibleImages);

      return true;
    }

    log.debug(
        "No new visible images in album {} for subscription {} (was: {}, now: {})",
        album.getName(),
        subscription.getId(),
        visibleCountBefore,
        visibleCountNow);

    return false;
  }

  /**
   * Count visible images based on tag filtering rules. If beforeTime is provided, only count images
   * that existed and were visible before that time.
   *
   * <p>Tag visibility rules (excluding 'no_tag' which is a special marker): - If no images have
   * real tags: all images are visible - If at least one image has real tags: only images WITH real
   * tags are visible
   *
   * <p>A file is considered to "have real tags at time T" if it has at least one ImageTag (where
   * tag.name != 'no_tag') with taggedAt < T
   *
   * @param allFiles All files in the album (with tags eagerly loaded)
   * @param beforeTime Optional cutoff time - only count images visible before this time
   * @return Count of visible images
   */
  private int countVisibleImages(List<FileMetadata> allFiles, Instant beforeTime) {
    final String NO_TAG = FileStorageService.NO_TAG;

    if (beforeTime == null) {
      // Current state - simple logic
      if (allFiles.isEmpty()) {
        return 0;
      }

      // Check if any image has real tags (excluding 'no_tag')
      boolean anyImageHasRealTags =
          allFiles.stream().anyMatch(file -> hasRealTags(file.getImageTags(), NO_TAG));

      if (!anyImageHasRealTags) {
        // No real tags exist - all images are visible
        return allFiles.size();
      } else {
        // At least one image has real tags - only count images WITH real tags
        return (int)
            allFiles.stream().filter(file -> hasRealTags(file.getImageTags(), NO_TAG)).count();
      }
    }

    // Historical state - need to reconstruct state at beforeTime
    // Only consider files that were uploaded before the cutoff
    List<FileMetadata> filesExistedBefore =
        allFiles.stream().filter(file -> file.getUploadedAt().isBefore(beforeTime)).toList();

    if (filesExistedBefore.isEmpty()) {
      return 0;
    }

    // Check if any file had real tags at that time
    // A file "had real tags" if it has at least one ImageTag (where tag.name != 'no_tag') with
    // taggedAt < beforeTime
    boolean anyImageHadRealTags =
        filesExistedBefore.stream()
            .anyMatch(file -> hasRealTagsBefore(file.getImageTags(), NO_TAG, beforeTime));

    if (!anyImageHadRealTags) {
      // No real tags existed at that time - all files were visible
      return filesExistedBefore.size();
    } else {
      // At least one file had real tags - only count files that had real tags at that time
      return (int)
          filesExistedBefore.stream()
              .filter(file -> hasRealTagsBefore(file.getImageTags(), NO_TAG, beforeTime))
              .count();
    }
  }

  /**
   * Check if a file has any real tags (excluding 'no_tag')
   *
   * @param imageTags The image tags to check
   * @param noTagValue The value to exclude ('no_tag')
   * @return true if file has at least one real tag
   */
  private boolean hasRealTags(java.util.List<ImageTag> imageTags, String noTagValue) {
    return imageTags.stream().anyMatch(imageTag -> !noTagValue.equals(imageTag.getTag().getName()));
  }

  /**
   * Check if a file had any real tags before a specific time
   *
   * @param imageTags The image tags to check
   * @param noTagValue The value to exclude ('no_tag')
   * @param beforeTime The cutoff time
   * @return true if file had at least one real tag before the time
   */
  private boolean hasRealTagsBefore(
      java.util.List<ImageTag> imageTags, String noTagValue, Instant beforeTime) {
    return imageTags.stream()
        .anyMatch(
            imageTag ->
                !noTagValue.equals(imageTag.getTag().getName())
                    && imageTag.getTaggedAt().isBefore(beforeTime));
  }

  /**
   * Check if album owner has created new albums and send notification if needed
   *
   * @param subscription The subscription to check
   * @return true if notification was sent
   */
  private boolean checkAndNotifyNewAlbums(AlbumSubscription subscription) {
    Album originalAlbum = subscription.getAlbum();
    User albumOwner = originalAlbum.getUser();
    Instant lastNotified = subscription.getLastNotifiedAt();

    // If never notified, use subscription creation time
    if (lastNotified == null) {
      lastNotified = subscription.getCreatedAt();
    }

    // Find new albums created by the owner after last notification
    List<Album> newAlbums = albumRepository.findByUserAndCreatedAtAfter(albumOwner, lastNotified);

    // Remove the original album from the list if it's included
    newAlbums.removeIf(album -> album.getId().equals(originalAlbum.getId()));

    if (!newAlbums.isEmpty()) {
      log.info(
          "Found {} new albums from user {} for subscription {}",
          newAlbums.size(),
          albumOwner.getEmail(),
          subscription.getId());

      // Send notification for each new album that has at least one visible image
      // In a real scenario, you might want to batch these into one email
      boolean anyNotificationSent = false;
      for (Album newAlbum : newAlbums) {
        // Only notify about albums with share tokens (public albums) and at least one visible image
        if (newAlbum.getShareToken() != null && !newAlbum.getShareToken().isEmpty()) {
          // Get all files in the new album
          List<FileMetadata> albumFiles =
              fileMetadataRepository.findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(
                  newAlbum.getShareToken());

          // Check if album has at least one visible image
          int visibleCount = countVisibleImages(albumFiles, null);

          if (visibleCount > 0) {
            log.info(
                "Sending new album notification for album {} with {} visible images",
                newAlbum.getName(),
                visibleCount);
            emailService.sendNewAlbumNotification(
                subscription.getEmail(),
                albumOwner.getEmail(),
                newAlbum.getName(),
                newAlbum.getShareToken(),
                subscription.getUnsubscribeToken());

            // Send push notification
            apnsService.sendNewAlbumNotification(
                subscription.getEmail(),
                albumOwner.getEmail(),
                newAlbum.getName(),
                newAlbum.getShareToken());

            anyNotificationSent = true;
          } else {
            log.debug(
                "Skipping new album notification for album {} - no visible images",
                newAlbum.getName());
          }
        }
      }

      return anyNotificationSent;
    }

    return false;
  }
}
