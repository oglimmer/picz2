/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConfigurationProperties(prefix = "jobs")
@Data
public class JobsProperties {

  private final Poll poll = new Poll();
  private final Lease lease = new Lease();
  private final Backpressure backpressure = new Backpressure();

  /** N=3 per D15: a transient failure gets two retries before going to DEAD_LETTER. */
  private int maxAttempts = 3;

  @Data
  public static class Poll {
    /** D6: 2 s. Invisible relative to the cost of a transcode. */
    private long intervalMs = 2000;
  }

  @Data
  public static class Lease {
    /** D5: 15 min default. Long enough for a 1080p transcode on the Pi. */
    private int seconds = 900;
  }

  @Data
  public static class Backpressure {
    /** Filter rejects new uploads with 503 once (QUEUED + PROCESSING) crosses this. */
    private int queueDepthThreshold = 200;

    /** Refresh interval for the cached gauge. */
    private long refreshMs = 1000;
  }
}
