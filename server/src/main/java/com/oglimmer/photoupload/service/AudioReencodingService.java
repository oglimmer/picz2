/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Service for re-encoding audio files using ffmpeg to ensure spec compliance. Browser-recorded
 * audio may not be 100% according to spec, so we re-encode using Opus codec with proper settings.
 *
 * <p>Also produces the AAC sibling that Apple clients need — see {@link #transcodeToAac}.
 */
@Service
@Slf4j
public class AudioReencodingService {

  /**
   * Re-encode a WebM audio file using ffmpeg with Opus codec. The original file is replaced with
   * the re-encoded version.
   *
   * @param audioPath Path to the audio file to re-encode
   * @throws IOException if re-encoding fails
   */
  public void reencodeAudio(Path audioPath) throws IOException {
    if (!Files.exists(audioPath)) {
      throw new IOException("Audio file does not exist: " + audioPath);
    }

    // Create temporary file for re-encoded output
    // Keep the .webm extension so ffmpeg can recognize the format
    String filename = audioPath.getFileName().toString();
    String tempFilename;
    int lastDot = filename.lastIndexOf('.');
    if (lastDot > 0) {
      tempFilename = filename.substring(0, lastDot) + "_tmp" + filename.substring(lastDot);
    } else {
      tempFilename = filename + "_tmp";
    }
    Path tempPath = audioPath.resolveSibling(tempFilename);

    try {
      List<String> command = new ArrayList<>();
      command.add("ffmpeg");
      command.add("-y"); // Overwrite output file
      command.add("-fflags");
      command.add("+genpts"); // Generate presentation timestamps
      command.add("-i");
      command.add(audioPath.toAbsolutePath().toString()); // Input file
      command.add("-c:a");
      command.add("libopus"); // Use Opus codec
      command.add("-b:a");
      command.add("64k"); // Bitrate
      command.add("-vbr");
      command.add("on"); // Variable bitrate
      command.add("-application");
      command.add("audio"); // Optimize for audio
      command.add("-avoid_negative_ts");
      command.add("make_zero"); // Avoid negative timestamps
      command.add(tempPath.toAbsolutePath().toString()); // Output file

      log.info("Re-encoding audio file: {}", audioPath.getFileName());
      runFfmpeg(command, "re-encoding");

      // Re-encoding successful, replace original file
      Files.delete(audioPath);
      Files.move(tempPath, audioPath);
      log.info("Successfully re-encoded audio file: {}", audioPath.getFileName());
    } catch (IOException e) {
      Files.deleteIfExists(tempPath);
      throw e;
    }
  }

  /**
   * Transcode any audio file to AAC in an MP4/{@code .m4a} container.
   *
   * <p>This exists because Apple's media stack has no WebM demuxer at all — {@code
   * AudioFileOpenURL} fails outright on the Opus/WebM master, so an iPhone cannot play a commentary
   * no matter what it does. Opus stays the master for the web; this is the sibling rendition served
   * to clients that ask for {@code format=m4a}.
   *
   * <p>{@code -movflags +faststart} moves the MP4 index to the front, so a player can start on the
   * first bytes instead of waiting for the whole file.
   *
   * @param source any audio file ffmpeg can read (in practice the Opus/WebM master)
   * @param destination where to write the {@code .m4a}; overwritten if it exists
   * @throws IOException if transcoding fails
   */
  public void transcodeToAac(Path source, Path destination) throws IOException {
    if (!Files.exists(source)) {
      throw new IOException("Audio file does not exist: " + source);
    }

    List<String> command = new ArrayList<>();
    command.add("ffmpeg");
    command.add("-y");
    command.add("-fflags");
    command.add("+genpts");
    command.add("-i");
    command.add(source.toAbsolutePath().toString());
    command.add("-c:a");
    command.add("aac");
    command.add("-b:a");
    command.add("96k"); // Opus at 64k is roughly AAC at 96k; keeps the voice from degrading twice
    command.add("-ac");
    command.add("1"); // Commentary is a single voice — stereo would double the size for nothing
    command.add("-movflags");
    command.add("+faststart");
    command.add("-avoid_negative_ts");
    command.add("make_zero");
    command.add(destination.toAbsolutePath().toString());

    log.info("Transcoding audio to AAC: {} → {}", source.getFileName(), destination.getFileName());
    try {
      runFfmpeg(command, "AAC transcode");
    } catch (IOException e) {
      Files.deleteIfExists(destination);
      throw e;
    }
    log.info("Successfully transcoded audio to AAC: {}", destination.getFileName());
  }

  /**
   * Runs one ffmpeg invocation and turns a non-zero exit into an {@link IOException} carrying the
   * captured output — ffmpeg says why it failed on stderr and nowhere else.
   */
  private void runFfmpeg(List<String> command, String what) throws IOException {
    log.debug("ffmpeg command: {}", String.join(" ", command));

    ProcessBuilder processBuilder = new ProcessBuilder(command);
    processBuilder.redirectErrorStream(true);
    Process process = processBuilder.start();

    StringBuilder output = new StringBuilder();
    try (BufferedReader reader =
        new BufferedReader(new InputStreamReader(process.getInputStream()))) {
      String line;
      while ((line = reader.readLine()) != null) {
        output.append(line).append("\n");
      }
    }

    int exitCode;
    try {
      exitCode = process.waitFor();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new IOException("ffmpeg " + what + " was interrupted", e);
    }

    if (exitCode != 0) {
      log.error("ffmpeg {} failed with exit code {}: {}", what, exitCode, output);
      throw new IOException("ffmpeg " + what + " failed with exit code " + exitCode);
    }
  }
}
