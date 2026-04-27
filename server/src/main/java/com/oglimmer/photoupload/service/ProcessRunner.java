/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.List;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;

/**
 * Runs an external command, captures combined stdout/stderr, and enforces a timeout. On timeout the
 * process is force-killed; previous code paths blocked indefinitely on hung ffmpeg invocations.
 */
@Slf4j
final class ProcessRunner {

  private ProcessRunner() {}

  record Result(int exitCode, String output, boolean timedOut) {
    boolean success() {
      return !timedOut && exitCode == 0;
    }
  }

  static Result run(List<String> command, long timeout, TimeUnit unit) throws IOException {
    ProcessBuilder pb = new ProcessBuilder(command).redirectErrorStream(true);
    Process process = pb.start();

    StringBuilder out = new StringBuilder();
    try (BufferedReader reader =
        new BufferedReader(new InputStreamReader(process.getInputStream()))) {
      String line;
      while ((line = reader.readLine()) != null) {
        out.append(line).append('\n');
      }
    }

    boolean finished;
    try {
      finished = process.waitFor(timeout, unit);
    } catch (InterruptedException e) {
      process.destroyForcibly();
      Thread.currentThread().interrupt();
      return new Result(-1, out.toString(), false);
    }

    if (!finished) {
      log.error(
          "Process exceeded timeout {} {} and was killed: {}",
          timeout,
          unit.name().toLowerCase(),
          command.get(0));
      process.destroyForcibly();
      try {
        process.waitFor(5, TimeUnit.SECONDS);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
      return new Result(-1, out.toString(), true);
    }
    return new Result(process.exitValue(), out.toString(), false);
  }
}
