/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.config;

import java.time.ZoneId;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Configures how a photo's timezone-less capture time is turned into an instant.
 *
 * <p>EXIF {@code DateTimeOriginal} is a bare wall clock ("2026:08:17 14:23:11") with no zone.
 * Modern iPhones additionally write {@code OffsetTimeOriginal} (0x9011), which pins it to a real
 * instant, and that tag wins whenever it is present. {@link #fallbackZone} is only consulted for
 * photos that lack it — older cameras, or files whose tags were stripped by an editor.
 */
@Configuration
@ConfigurationProperties(prefix = "capture-date")
@Data
public class CaptureDateProperties {

  /**
   * Zone assumed for a photo whose EXIF carries no UTC offset. Defaults to the zone most of this
   * install's legacy photos were taken in — UTC would silently shift them by the offset instead.
   */
  private ZoneId fallbackZone = ZoneId.of("Europe/Berlin");
}
