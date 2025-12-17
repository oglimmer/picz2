/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConfigurationProperties(prefix = "app.apns")
@Data
public class ApnsConfig {
  private boolean enabled;
  private String keyPath;
  private String keyId;
  private String teamId;
  private String topic;
  private boolean production;
}
