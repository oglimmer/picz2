/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AlbumSubscription;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

@Repository
public interface AlbumSubscriptionRepository extends JpaRepository<AlbumSubscription, Long> {

  Optional<AlbumSubscription> findByEmailAndAlbum(String email, Album album);

  Optional<AlbumSubscription> findByConfirmationToken(String confirmationToken);

  Optional<AlbumSubscription> findByUnsubscribeToken(String unsubscribeToken);

  // Find all active and confirmed subscriptions for notification processing
  @Query(
      "SELECT s FROM AlbumSubscription s WHERE s.active = true AND s.confirmed = true ORDER BY s.id")
  List<AlbumSubscription> findAllActiveAndConfirmed();
}
