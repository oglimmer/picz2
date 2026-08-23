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
    /**
     * D5, raised 900 -> 2700 on 2026-08-23. The old 15 min was sized for a 1080p transcode, but the
     * lease has to cover the <em>source</em> decode too: a 4K iPhone clip took 17 minutes end to
     * end, so the second worker declared the first one dead mid-encode and restarted the job from
     * scratch. Both replicas then transcoded the same asset at once and the attempt counter climbed
     * toward DEAD_LETTER on a job that was actually progressing (asset 6720).
     *
     * <p>The cost is the other direction: a worker that really dies now leaves its job unclaimed
     * for up to 45 min instead of 15. That is the right trade here — a pod loss is rare, a long
     * video is not, and a stolen lease burns two CPUs and can still lose the asset.
     */
    private int seconds = 2700;
  }

  @Data
  public static class Backpressure {
    /** Filter rejects new uploads with 503 once (QUEUED + PROCESSING) crosses this. */
    private int queueDepthThreshold = 200;

    /** Refresh interval for the cached gauge. */
    private long refreshMs = 1000;
  }
}
