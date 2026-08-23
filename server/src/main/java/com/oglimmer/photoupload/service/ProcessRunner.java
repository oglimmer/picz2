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
 *
 * <p>The output is drained on a <em>separate</em> thread so the timeout can actually be enforced.
 * An earlier version read the stream to EOF on the calling thread and only then called {@code
 * waitFor(timeout)} — but a child's stdout does not reach EOF until the child exits, so the read
 * loop had already outlived the deadline by the time the deadline was checked and {@code waitFor}
 * returned instantly. The timeout was dead code: a 17-minute transcode sailed past a 15-minute
 * limit unremarked (asset 6720, 2026-08-23), and a genuinely hung child would have pinned a worker
 * thread forever — the exact failure this class exists to prevent.
 *
 * <p>Draining concurrently is not optional. The pipe between parent and child holds only a few
 * dozen KiB; a child that fills it blocks in {@code write()} and never exits, so a parent that
 * waits before reading deadlocks against a child that writes before exiting. That deadlock is why
 * the original drained first, and any fix has to keep the drain running while the clock runs.
 */
@Slf4j
final class ProcessRunner {

  private ProcessRunner() {}

  /**
   * Ceiling on captured output. Callers only ever log this text or match it for a diagnostic, so
   * truncation costs nothing — whereas a chatty or looping child (ffmpeg re-emitting a per-frame
   * warning, say) could otherwise grow the buffer without bound inside a 2 GiB worker for the full
   * length of a 15-minute timeout. Newly relevant now that the timeout really does let a runaway
   * child keep running until the deadline instead of being bounded by its own prompt exit.
   */
  private static final int MAX_OUTPUT_CHARS = 256 * 1024;

  /** Grace period for the drain thread to notice the closed stream after a force-kill. */
  private static final long DRAIN_JOIN_MILLIS = 5_000;

  record Result(int exitCode, String output, boolean timedOut) {
    boolean success() {
      return !timedOut && exitCode == 0;
    }
  }

  static Result run(List<String> command, long timeout, TimeUnit unit) throws IOException {
    ProcessBuilder pb = new ProcessBuilder(command).redirectErrorStream(true);
    Process process = pb.start();

    // StringBuffer, not StringBuilder: the drain thread appends while this thread may read the
    // accumulated text after a join that timed out, so the buffer needs its own synchronisation.
    StringBuffer out = new StringBuffer();
    Thread drain =
        new Thread(
            () -> {
              try (BufferedReader reader =
                  new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                  if (out.length() < MAX_OUTPUT_CHARS) {
                    out.append(line).append('\n');
                  }
                }
              } catch (IOException e) {
                // Expected after destroyForcibly closes the pipe mid-read. Nothing to salvage:
                // whatever was already appended is what the caller gets.
                log.debug("Output drain ended for {}: {}", command.get(0), e.toString());
              }
            },
            "proc-drain-" + command.get(0));
    drain.setDaemon(true);
    drain.start();

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
      joinDrain(drain);
      return new Result(-1, out.toString(), true);
    }

    // The child has exited, so its stdout is at EOF and the drain thread is about to finish. Join
    // before reading `out` so the caller sees the tail of the output and not a partial buffer —
    // an ImageMagick or ffmpeg failure puts its reason on the last line.
    joinDrain(drain);
    return new Result(process.exitValue(), out.toString(), false);
  }

  private static void joinDrain(Thread drain) {
    try {
      drain.join(DRAIN_JOIN_MILLIS);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
}
