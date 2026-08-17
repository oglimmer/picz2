/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.CaptureDateProperties;
import com.oglimmer.photoupload.entity.CaptureDateSource;
import com.oglimmer.photoupload.model.CaptureDate;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneId;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * The bug this guards: EXIF {@code DateTimeOriginal} carries no zone, and metadata-extractor's
 * single-argument {@code getDate(tag)} silently assumes GMT, so a photo taken at 14:23 local was
 * stored as 14:23Z — two hours later than it happened. Videos were always stored as true instants,
 * so photos and videos ended up on different clocks and sheared apart when an album was sorted by
 * capture date.
 */
class CaptureDateExtractorTest {

  @TempDir Path tempDir;

  private CaptureDateExtractor extractor(String fallbackZone) {
    CaptureDateProperties props = new CaptureDateProperties();
    props.setFallbackZone(ZoneId.of(fallbackZone));
    return new CaptureDateExtractor(props, mock(ThumbnailService.class));
  }

  @Test
  void offsetTimeOriginalPinsThePhotoToTheRightInstant() throws IOException {
    Path jpeg = writeJpeg("dto-with-offset.jpg", "2026:08:17 14:23:11", "+02:00");

    CaptureDate result = extractor("Europe/Berlin").extract(jpeg, "image/jpeg");

    assertThat(result.instant()).isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
    assertThat(result.source()).isEqualTo(CaptureDateSource.EXIF_OFFSET_TIME);
  }

  @Test
  void colonLessOffsetTagIsAccepted() throws IOException {
    Path jpeg = writeJpeg("dto-colonless.jpg", "2026:08:17 14:23:11", "+0200");

    CaptureDate result = extractor("UTC").extract(jpeg, "image/jpeg");

    assertThat(result.instant()).isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
    assertThat(result.source()).isEqualTo(CaptureDateSource.EXIF_OFFSET_TIME);
  }

  @Test
  void fallbackZoneAppliesWhenTheOffsetTagIsMissing() throws IOException {
    Path jpeg = writeJpeg("dto-only.jpg", "2026:08:17 14:23:11", null);

    CaptureDate result = extractor("Europe/Berlin").extract(jpeg, "image/jpeg");

    assertThat(result.instant()).isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
    assertThat(result.source()).isEqualTo(CaptureDateSource.EXIF_FALLBACK_ZONE);
  }

  /** A fixed offset would be wrong half the year; the zone has to resolve DST per date. */
  @Test
  void fallbackZoneRespectsDstForTheCaptureDate() throws IOException {
    Path jpeg = writeJpeg("winter.jpg", "2026:01:17 14:23:11", null);

    CaptureDate result = extractor("Europe/Berlin").extract(jpeg, "image/jpeg");

    assertThat(result.instant()).isEqualTo(Instant.parse("2026-01-17T13:23:11Z"));
  }

  /**
   * Setting the fallback to UTC reproduces the pre-fix behaviour, which is the documented escape.
   */
  @Test
  void utcFallbackKeepsTheWallClockAsIs() throws IOException {
    Path jpeg = writeJpeg("utc-fallback.jpg", "2026:08:17 14:23:11", null);

    CaptureDate result = extractor("UTC").extract(jpeg, "image/jpeg");

    assertThat(result.instant()).isEqualTo(Instant.parse("2026-08-17T14:23:11Z"));
  }

  @Test
  void unparseableOffsetTagFallsBackToTheConfiguredZone() throws IOException {
    Path jpeg = writeJpeg("bad-offset.jpg", "2026:08:17 14:23:11", "not-an-offset");

    CaptureDate result = extractor("Europe/Berlin").extract(jpeg, "image/jpeg");

    assertThat(result.instant()).isEqualTo(Instant.parse("2026-08-17T12:23:11Z"));
    assertThat(result.source()).isEqualTo(CaptureDateSource.EXIF_FALLBACK_ZONE);
  }

  @Test
  void fileWithoutExifYieldsNone() throws IOException {
    Path notAnImage =
        Files.write(tempDir.resolve("empty.jpg"), new byte[] {(byte) 0xFF, (byte) 0xD8});

    CaptureDate result = extractor("Europe/Berlin").extract(notAnImage, "image/jpeg");

    assertThat(result.isPresent()).isFalse();
    assertThat(result.source()).isEqualTo(CaptureDateSource.NONE);
  }

  @Test
  void videosGoThroughFfprobe() {
    CaptureDateProperties props = new CaptureDateProperties();
    ThumbnailService thumbnails = mock(ThumbnailService.class);
    Path video = tempDir.resolve("clip.mov");
    CaptureDate probed =
        CaptureDate.of(Instant.parse("2026-08-17T12:23:11Z"), CaptureDateSource.QUICKTIME_LOCAL);
    when(thumbnails.extractVideoCreationDate(video)).thenReturn(probed);

    assertThat(new CaptureDateExtractor(props, thumbnails).extract(video, "video/quicktime"))
        .isEqualTo(probed);
  }

  @Test
  void nonMediaMimeTypesAreNotProbedAtAll() {
    ThumbnailService thumbnails = mock(ThumbnailService.class);
    CaptureDateExtractor svc = new CaptureDateExtractor(new CaptureDateProperties(), thumbnails);

    assertThat(svc.extract(tempDir.resolve("notes.pdf"), "application/pdf").isPresent()).isFalse();
    verifyNoInteractions(thumbnails);
  }

  /**
   * Writes a JPEG carrying nothing but an EXIF APP1 segment — enough for metadata-extractor, and it
   * keeps the test free of a binary fixture. Layout: SOI, APP1("Exif\0\0" + little-endian TIFF with
   * IFD0 → Exif SubIFD holding DateTimeOriginal and optionally OffsetTimeOriginal), EOI.
   */
  private Path writeJpeg(String name, String dateTimeOriginal, String offsetTimeOriginal)
      throws IOException {
    byte[] dto = nulTerminated(dateTimeOriginal);
    byte[] offset = offsetTimeOriginal == null ? null : nulTerminated(offsetTimeOriginal);
    int entryCount = offset == null ? 1 : 2;

    int ifd0Offset = 8;
    int ifd0Size = 2 + 12 + 4;
    int subIfdOffset = ifd0Offset + ifd0Size;
    int subIfdSize = 2 + 12 * entryCount + 4;
    int dataOffset = subIfdOffset + subIfdSize;

    ByteBuffer tiff =
        ByteBuffer.allocate(dataOffset + dto.length + (offset == null ? 0 : offset.length))
            .order(ByteOrder.LITTLE_ENDIAN);
    tiff.put("II".getBytes(StandardCharsets.US_ASCII)).putShort((short) 42).putInt(ifd0Offset);
    // IFD0: a single ExifIFDPointer (0x8769, LONG) at the SubIFD.
    tiff.putShort((short) 1);
    putEntry(tiff, 0x8769, 4, 1, subIfdOffset);
    tiff.putInt(0);
    // Exif SubIFD: ASCII tags, both longer than 4 bytes so both live in the data area.
    tiff.putShort((short) entryCount);
    putEntry(tiff, 0x9003, 2, dto.length, dataOffset);
    if (offset != null) {
      putEntry(tiff, 0x9011, 2, offset.length, dataOffset + dto.length);
    }
    tiff.putInt(0);
    tiff.put(dto);
    if (offset != null) {
      tiff.put(offset);
    }

    byte[] app1Payload = concat("Exif\0\0".getBytes(StandardCharsets.US_ASCII), tiff.array());
    ByteBuffer jpeg = ByteBuffer.allocate(2 + 4 + app1Payload.length + 2);
    jpeg.put((byte) 0xFF).put((byte) 0xD8);
    jpeg.put((byte) 0xFF).put((byte) 0xE1).putShort((short) (app1Payload.length + 2));
    jpeg.put(app1Payload);
    jpeg.put((byte) 0xFF).put((byte) 0xD9);
    return Files.write(tempDir.resolve(name), jpeg.array());
  }

  private static void putEntry(ByteBuffer buf, int tag, int type, int count, int valueOffset) {
    buf.putShort((short) tag).putShort((short) type).putInt(count).putInt(valueOffset);
  }

  private static byte[] nulTerminated(String value) {
    return (value + "\0").getBytes(StandardCharsets.US_ASCII);
  }

  private static byte[] concat(byte[] a, byte[] b) {
    byte[] out = new byte[a.length + b.length];
    System.arraycopy(a, 0, out, 0, a.length);
    System.arraycopy(b, 0, out, a.length, b.length);
    return out;
  }
}
