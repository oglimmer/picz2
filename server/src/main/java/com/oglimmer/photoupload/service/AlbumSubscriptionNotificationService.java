/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import com.oglimmer.photoupload.config.Profiles;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AlbumSubscription;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ImageTag;
import com.oglimmer.photoupload.entity.SystemTags;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.AlbumSubscriptionRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import java.time.Instant;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Service for processing album subscription notifications on a schedule */
@Profile(Profiles.API)
@Service
@Slf4j
@RequiredArgsConstructor
public class AlbumSubscriptionNotificationService {

  private final AlbumSubscriptionRepository subscriptionRepository;
  private final FileMetadataRepository fileMetadataRepository;
  private final AlbumRepository albumRepository;
  private final EmailService emailService;
  private final ApnsService apnsService;

  /**
   * Process all subscriptions and send notifications for updates. Runs at minute 0 of every 6th
   * hour. It was left on a once-a-minute cron after a debugging session (noted 2026-09-01), which
   * loaded every file of every subscribed album sixty times an hour.
   */
  @Scheduled(cron = "0 0 */6 * * *")
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

    // An unpublished album is dark: its share link 404s, so a mail pointing at it would send the
    // reader nowhere. Subscriptions are kept, not cancelled — publishing again resumes them.
    if (!album.isPublished()) {
      log.debug("Skipping updates for unpublished album {}", album.getName());
      return false;
    }

    Instant lastNotified = subscription.getLastNotifiedAt();

    // If never notified, use subscription creation time
    if (lastNotified == null) {
      lastNotified = subscription.getCreatedAt();
    }

    // Get all files in the album, minus the ones in the holding pen (D70). A `hidden` asset is
    // not on the share page, so a mail announcing it would send the reader to an album that looks
    // unchanged. Dropping it from BOTH counts also gives the behaviour we want on release: when
    // the owner reviews it and takes `hidden` off, the file joins the visible set and the next
    // sweep sees the count rise — one mail, at the moment of publishing rather than of shooting.
    List<FileMetadata> allFiles =
        fileMetadataRepository
            .findByAlbumShareTokenWithTagsOrderByDisplayOrderAsc(album.getShareToken())
            .stream()
            .filter(file -> !isHidden(file))
            .toList();

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
   * <p>Tag visibility rules: - If no images have tags: all images are visible - If at least one
   * image has tags: only images WITH tags are visible
   *
   * <p>A file is considered to "have tags at time T" if it has at least one ImageTag with taggedAt
   * < T. Since D68 every newly uploaded asset carries a tag from the moment it is registered, so in
   * practice a fresh album counts every asset it is given — and since D70 the hidden ones are not
   * given to it at all, having been filtered out by the caller.
   *
   * @param allFiles All files in the album (with tags eagerly loaded)
   * @param beforeTime Optional cutoff time - only count images visible before this time
   * @return Count of visible images
   */
  private int countVisibleImages(List<FileMetadata> allFiles, Instant beforeTime) {
    if (beforeTime == null) {
      // Current state - simple logic
      if (allFiles.isEmpty()) {
        return 0;
      }

      // Check if any image has tags
      boolean anyImageHasTags = allFiles.stream().anyMatch(file -> hasTags(file.getImageTags()));

      if (!anyImageHasTags) {
        // No tags exist - all images are visible
        return allFiles.size();
      } else {
        // At least one image has tags - only count images WITH tags
        return (int) allFiles.stream().filter(file -> hasTags(file.getImageTags())).count();
      }
    }

    // Historical state - need to reconstruct state at beforeTime
    // Only consider files that were uploaded before the cutoff
    List<FileMetadata> filesExistedBefore =
        allFiles.stream().filter(file -> file.getUploadedAt().isBefore(beforeTime)).toList();

    if (filesExistedBefore.isEmpty()) {
      return 0;
    }

    // Check if any file had tags at that time
    // A file "had tags" if it has at least one ImageTag with taggedAt < beforeTime
    boolean anyImageHadTags =
        filesExistedBefore.stream()
            .anyMatch(file -> hasTagsBefore(file.getImageTags(), beforeTime));

    if (!anyImageHadTags) {
      // No tags existed at that time - all files were visible
      return filesExistedBefore.size();
    } else {
      // At least one file had tags - only count files that had tags at that time
      return (int)
          filesExistedBefore.stream()
              .filter(file -> hasTagsBefore(file.getImageTags(), beforeTime))
              .count();
    }
  }

  /** True while the asset carries the {@code hidden} system tag (D70). */
  private static boolean isHidden(FileMetadata file) {
    return file.getImageTags().stream()
        .anyMatch(it -> SystemTags.HIDDEN.equals(it.getTag().getName()));
  }

  /**
   * Check if a file has any tags
   *
   * @param imageTags The image tags to check
   * @return true if file has at least one tag
   */
  private boolean hasTags(java.util.List<ImageTag> imageTags) {
    return !imageTags.isEmpty();
  }

  /**
   * Check if a file had any tags before a specific time
   *
   * @param imageTags The image tags to check
   * @param beforeTime The cutoff time
   * @return true if file had at least one tag before the time
   */
  private boolean hasTagsBefore(java.util.List<ImageTag> imageTags, Instant beforeTime) {
    return imageTags.stream().anyMatch(imageTag -> imageTag.getTaggedAt().isBefore(beforeTime));
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

    // Find albums the owner has published since the last notification. Publication date, not
    // creation date: a draft started weeks ago is new to a subscriber on the day it goes live.
    List<Album> newAlbums =
        albumRepository.findByUserAndPublishedTrueAndPublishedAtAfter(albumOwner, lastNotified);

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
        // The query already filtered to published albums.
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
