/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.repository;

import com.oglimmer.photoupload.entity.DeviceToken;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface DeviceTokenRepository extends JpaRepository<DeviceToken, Long> {
  Optional<DeviceToken> findByDeviceToken(String deviceToken);

  List<DeviceToken> findByEmailAndIsActiveTrue(String email);

  List<DeviceToken> findByIsActiveTrueAndFailureCountLessThan(int maxFailures);

  @Modifying
  @Query("UPDATE DeviceToken dt SET dt.isActive = false WHERE dt.failureCount >= :maxFailures")
  int deactivateFailedTokens(@Param("maxFailures") int maxFailures);
}
