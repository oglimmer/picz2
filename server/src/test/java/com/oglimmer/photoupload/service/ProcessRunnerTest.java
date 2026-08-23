/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.DisabledOnOs;
import org.junit.jupiter.api.condition.OS;

/**
 * Guards the timeout contract of {@link ProcessRunner}. Uses {@code sh}, which every image and dev
 * machine here already has — the point is process lifecycle, not any particular tool.
 */
@DisabledOnOs(OS.WINDOWS)
class ProcessRunnerTest {

  @Test
  @DisplayName("a child that outlives the timeout is killed and reported as timedOut")
  void timeoutIsEnforced() throws IOException {
    // Regression: the runner used to drain stdout to EOF on the calling thread before calling
    // waitFor(timeout). A child's stdout only reaches EOF when the child exits, so the read
    // blocked for the child's full lifetime and waitFor then returned true immediately — the
    // timeout never fired. This sleeps well past its 1s deadline; the old code returned
    // success() after ~10s, the fixed code returns timedOut after ~1s.
    Instant start = Instant.now();
    ProcessRunner.Result r =
        ProcessRunner.run(List.of("sh", "-c", "sleep 10"), 1, TimeUnit.SECONDS);
    Duration elapsed = Duration.between(start, Instant.now());

    assertThat(r.timedOut()).isTrue();
    assertThat(r.success()).isFalse();
    assertThat(elapsed).isLessThan(Duration.ofSeconds(8));
  }

  @Test
  @DisplayName("a child that holds the pipe open past the timeout is still killed")
  void timeoutIsEnforcedWhileChildKeepsWriting() throws IOException {
    // The pipe stays hot the whole time, so this fails for a fix that merely moves the drain
    // after waitFor: that variant deadlocks or hangs instead of honouring the deadline.
    Instant start = Instant.now();
    ProcessRunner.Result r =
        ProcessRunner.run(
            List.of(
                "sh",
                "-c",
                "i=0; while [ $i -lt 200 ]; do echo line$i; sleep 0.05; i=$((i+1)); done"),
            1,
            TimeUnit.SECONDS);
    Duration elapsed = Duration.between(start, Instant.now());

    assertThat(r.timedOut()).isTrue();
    assertThat(elapsed).isLessThan(Duration.ofSeconds(8));
  }

  @Test
  @DisplayName("a child that finishes in time returns its exit code and full output")
  void successfulRunCapturesOutput() throws IOException {
    ProcessRunner.Result r =
        ProcessRunner.run(List.of("sh", "-c", "echo first; echo second"), 30, TimeUnit.SECONDS);

    assertThat(r.success()).isTrue();
    assertThat(r.exitCode()).isZero();
    assertThat(r.timedOut()).isFalse();
    // The tail matters: a tool's failure reason is on its last line, so the drain has to be
    // joined before the output is read.
    assertThat(r.output()).contains("first").contains("second");
  }

  @Test
  @DisplayName("stderr is captured and a non-zero exit is not success")
  void failureCapturesStderr() throws IOException {
    ProcessRunner.Result r =
        ProcessRunner.run(List.of("sh", "-c", "echo boom >&2; exit 3"), 30, TimeUnit.SECONDS);

    assertThat(r.success()).isFalse();
    assertThat(r.exitCode()).isEqualTo(3);
    assertThat(r.timedOut()).isFalse();
    assertThat(r.output()).contains("boom");
  }

  @Test
  @DisplayName("output far larger than the pipe buffer neither deadlocks nor grows without bound")
  void largeOutputIsCappedWithoutDeadlock() throws IOException {
    // ~1.4 MiB, well past both the OS pipe buffer (which would deadlock an undrained child)
    // and MAX_OUTPUT_CHARS (256 KiB).
    ProcessRunner.Result r =
        ProcessRunner.run(
            List.of(
                "sh",
                "-c",
                "i=0; while [ $i -lt 20000 ]; do echo 0123456789012345678901234567890123456789012345678901234567890123456789; i=$((i+1)); done"),
            60,
            TimeUnit.SECONDS);

    assertThat(r.success()).isTrue();
    assertThat(r.output().length()).isLessThan(400 * 1024);
  }
}
