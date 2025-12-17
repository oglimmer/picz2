/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "device_tokens")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class DeviceToken {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "device_token", nullable = false, unique = true)
  private String deviceToken;

  @Column(name = "email", nullable = false)
  private String email;

  @Column(name = "platform", nullable = false)
  private String platform = "ios";

  @Column(name = "app_version")
  private String appVersion;

  @Column(name = "device_model")
  private String deviceModel;

  @Column(name = "os_version")
  private String osVersion;

  @Column(name = "created_at", nullable = false)
  private Instant createdAt;

  @Column(name = "updated_at", nullable = false)
  private Instant updatedAt;

  @Column(name = "last_active_at")
  private Instant lastActiveAt;

  @Column(name = "is_active", nullable = false)
  private Boolean isActive = true;

  @Column(name = "failure_count", nullable = false)
  private Integer failureCount = 0;

  @Column(name = "last_failure_reason")
  private String lastFailureReason;

  @PrePersist
  protected void onCreate() {
    createdAt = Instant.now();
    updatedAt = Instant.now();
    lastActiveAt = Instant.now();
  }

  @PreUpdate
  protected void onUpdate() {
    updatedAt = Instant.now();
  }
}
