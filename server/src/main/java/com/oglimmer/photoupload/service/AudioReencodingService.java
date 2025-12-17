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
      // Build ffmpeg command
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
      log.debug("ffmpeg command: {}", String.join(" ", command));

      // Execute ffmpeg command
      ProcessBuilder processBuilder = new ProcessBuilder(command);
      processBuilder.redirectErrorStream(true);
      Process process = processBuilder.start();

      // Capture output for debugging
      StringBuilder output = new StringBuilder();
      try (BufferedReader reader =
          new BufferedReader(new InputStreamReader(process.getInputStream()))) {
        String line;
        while ((line = reader.readLine()) != null) {
          output.append(line).append("\n");
        }
      }

      int exitCode = process.waitFor();

      if (exitCode == 0) {
        // Re-encoding successful, replace original file
        Files.delete(audioPath);
        Files.move(tempPath, audioPath);
        log.info("Successfully re-encoded audio file: {}", audioPath.getFileName());
      } else {
        // Re-encoding failed, log error and clean up temp file
        log.error("ffmpeg re-encoding failed with exit code {}: {}", exitCode, output);
        Files.deleteIfExists(tempPath);
        throw new IOException("ffmpeg re-encoding failed with exit code " + exitCode);
      }

    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      Files.deleteIfExists(tempPath);
      throw new IOException("Audio re-encoding was interrupted", e);
    } catch (IOException e) {
      // Clean up temp file on any IO error
      Files.deleteIfExists(tempPath);
      throw e;
    }
  }
}
