import { ref, type Ref } from "vue";
import { useApi } from "./useApi";
import type { AlbumFile, ProcessingStatus } from "@/types";

interface PollEntry {
  fileId: number;
  attempts: number;
  // setTimeout handle so we can cancel on unmount or external refresh.
  timer: ReturnType<typeof setTimeout> | null;
}

/** Why a file stopped being polled. */
interface PollOutcome {
  status: ProcessingStatus | "GONE" | "GAVE_UP";
  error?: string;
}

export interface PollFailure {
  fileId: number;
  message: string;
}

interface Waiter {
  ids: Set<number>;
  failures: PollFailure[];
  resolve: (failures: PollFailure[]) => void;
  timer: ReturnType<typeof setTimeout>;
}

const TERMINAL_STATES: ProcessingStatus[] = ["DONE", "DEAD_LETTER"];

/**
 * Polls `/api/assets/{id}/status` for files whose backend processing is still in flight — right
 * after an upload, or after a rotate was enqueued. When a file reaches a terminal state the file is
 * mutated in place so dependents (gallery tiles keyed off the status) re-render. The cadence backs
 * off mildly: 1 s, 2 s, 4 s, capped at 8 s, with a hard cap on attempts so a job stuck in QUEUED
 * does not poll forever.
 *
 * `waitFor` lets a caller await a batch it just enqueued (bulk rotate) on the same poller, so the
 * status endpoint is never hit by two loops for one file. Per-instance state (see README.md).
 */
export interface ProcessingPollerComposable {
  pending: Ref<Set<number>>;
  watchFiles: (files: AlbumFile[]) => void;
  waitFor: (fileIds: number[], timeoutMs: number) => Promise<PollFailure[]>;
  stopAll: () => void;
}

export function useProcessingPoller(
  files: Ref<AlbumFile[]>,
): ProcessingPollerComposable {
  const { apiUrl, fetchWithAuth } = useApi();
  const pending = ref<Set<number>>(new Set());
  const entries = new Map<number, PollEntry>();
  const waiters = new Set<Waiter>();

  const MAX_ATTEMPTS = 30;
  const MAX_DELAY_MS = 8000;

  function nextDelay(attempt: number): number {
    return Math.min(1000 * 2 ** attempt, MAX_DELAY_MS);
  }

  async function pollOne(fileId: number) {
    const entry = entries.get(fileId);
    if (!entry) return;

    try {
      const res = await fetchWithAuth(`${apiUrl}/api/assets/${fileId}/status`);
      if (!res.ok) {
        // 404 means the file was deleted out from under us; stop polling.
        if (res.status === 404) {
          stopOne(fileId, { status: "GONE", error: "The file no longer exists" });
          return;
        }
        scheduleNext(entry);
        return;
      }
      const data = (await res.json()) as { processingStatus?: ProcessingStatus; error?: string };
      const status = data?.processingStatus;
      if (!status) {
        scheduleNext(entry);
        return;
      }
      const file = files.value.find((f) => f.id === fileId);
      if (file) {
        file.processingStatus = status;
      }
      if (TERMINAL_STATES.includes(status)) {
        stopOne(fileId, { status, error: data.error });
        return;
      }
      scheduleNext(entry);
    } catch {
      scheduleNext(entry);
    }
  }

  function scheduleNext(entry: PollEntry) {
    entry.attempts += 1;
    if (entry.attempts >= MAX_ATTEMPTS) {
      stopOne(entry.fileId, { status: "GAVE_UP", error: "Still processing — check back later" });
      return;
    }
    entry.timer = setTimeout(() => pollOne(entry.fileId), nextDelay(entry.attempts));
  }

  function stopOne(fileId: number, outcome?: PollOutcome) {
    const e = entries.get(fileId);
    if (e?.timer) clearTimeout(e.timer);
    entries.delete(fileId);
    pending.value.delete(fileId);
    // Force reactivity on the Set ref.
    pending.value = new Set(pending.value);
    if (outcome) settle(fileId, outcome);
  }

  /** Tells every waiter about a file that stopped being polled. */
  function settle(fileId: number, outcome: PollOutcome) {
    for (const waiter of [...waiters]) {
      if (!waiter.ids.has(fileId)) continue;
      waiter.ids.delete(fileId);
      if (outcome.status !== "DONE") {
        waiter.failures.push({
          fileId,
          message: outcome.error || "Processing failed on the worker",
        });
      }
      if (waiter.ids.size === 0) finish(waiter);
    }
  }

  function finish(waiter: Waiter) {
    clearTimeout(waiter.timer);
    waiters.delete(waiter);
    waiter.resolve(waiter.failures);
  }

  function startOne(fileId: number) {
    if (entries.has(fileId)) return;
    const entry: PollEntry = { fileId, attempts: 0, timer: null };
    entries.set(fileId, entry);
    pending.value.add(fileId);
    pending.value = new Set(pending.value);
    entry.timer = setTimeout(() => pollOne(fileId), nextDelay(0));
  }

  function watchFiles(input: AlbumFile[]) {
    for (const f of input) {
      if (f.processingStatus && !TERMINAL_STATES.includes(f.processingStatus)) {
        startOne(f.id);
      }
    }
  }

  /**
   * Resolves once every id has reached a terminal state, or after `timeoutMs`, with the ids that
   * did not end in DONE and why. Ids still pending at the timeout count as failures too, so a stuck
   * worker surfaces as a message instead of an infinite spinner.
   */
  function waitFor(fileIds: number[], timeoutMs: number): Promise<PollFailure[]> {
    return new Promise((resolve) => {
      const ids = new Set(fileIds);
      for (const id of ids) startOne(id);
      if (ids.size === 0) {
        resolve([]);
        return;
      }
      const waiter: Waiter = {
        ids,
        failures: [],
        resolve,
        timer: setTimeout(() => {
          for (const id of waiter.ids) {
            waiter.failures.push({ fileId: id, message: "Timed out waiting for the worker" });
          }
          waiter.ids.clear();
          finish(waiter);
        }, timeoutMs),
      };
      waiters.add(waiter);
    });
  }

  function stopAll() {
    for (const e of entries.values()) {
      if (e.timer) clearTimeout(e.timer);
    }
    entries.clear();
    pending.value = new Set();
    for (const waiter of [...waiters]) {
      waiter.ids.clear();
      finish(waiter);
    }
  }

  return { pending, watchFiles, waitFor, stopAll };
}
