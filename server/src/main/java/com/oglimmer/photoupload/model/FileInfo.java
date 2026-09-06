/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.model;

import com.oglimmer.photoupload.entity.ProcessingStatus;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class FileInfo {

  private Long id;
  private String originalName;
  private String filename;
  private String publicToken;
  private long size;
  private String mimetype;
  private String path;
  private Instant uploadedAt;
  private Instant exifDateTimeOriginal;

  /**
   * UTC offset in seconds at the capture location, or null when unknown. The gallery adds it to
   * {@link #exifDateTimeOriginal} to get the wall clock the camera saw, so a day section holds the
   * photos of that day *there*, not of that day in the viewer's timezone.
   */
  private Integer captureUtcOffsetSeconds;

  /**
   * The owner's caption for this asset, or null when there is none (D69). Public share responses
   * carry it too — it is written for the visitors, not for the owner.
   */
  private String caption;

  private Integer rotation;

  /**
   * When this asset was last auto-enhanced (D83), or null when it never was. Enhance rewrites the
   * original in place and compounds on itself, so the clients mark an enhanced asset and drop it
   * from a bulk enhance. Assets enhanced before the column existed read as null.
   */
  private Instant enhancedAt;

  private Integer displayOrder;
  private List<String> tags = new ArrayList<>();
  private Long albumId;
  private String albumName;
  private ProcessingStatus processingStatus;

  /**
   * Capture location in signed decimal degrees (WGS 84), or null when the asset carries none. Fed
   * straight to MapKit JS by the gallery's map filter, which uses the same reference frame.
   */
  private Double gpsLatitude;

  private Double gpsLongitude;

  /**
   * False when the original was purged from object storage by the retention CronJob (Phase 6 / Gap
   * 4-finish). Used by the UI to hide rotate/download-original actions; the gallery itself keeps
   * working from derivatives.
   */
  private boolean originalAvailable;
}
