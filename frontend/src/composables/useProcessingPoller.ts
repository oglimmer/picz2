import { ref, type Ref } from "vue";
import { useApi } from "./useApi";
import type { AlbumFile, ProcessingStatus } from "@/types";

interface PollEntry {
  fileId: number;
  attempts: number;
  // setTimeout handle so we can cancel on unmount or external refresh.
  timer: ReturnType<typeof setTimeout> | null;
}

const TERMINAL_STATES: ProcessingStatus[] = ["DONE", "FAILED", "DEAD_LETTER"];

/**
 * Poll /api/assets/{id}/status for files whose backend processing is still in flight after upload.
 * When a file reaches a terminal state, mutate the file in place so dependents (gallery img tags
 * keyed off `cacheBust`) re-render. The poll cadence backs off mildly: 1 s, 2 s, 4 s, capped at
 * 8 s, with a hard cap on attempts so a stuck FAILED case doesn't poll forever.
 */
export interface ProcessingPollerComposable {
  pending: Ref<Set<number>>;
  watchFiles: (files: AlbumFile[]) => void;
  stopAll: () => void;
}

export function useProcessingPoller(
  files: Ref<AlbumFile[]>,
): ProcessingPollerComposable {
  const { apiUrl, fetchWithAuth } = useApi();
  const pending = ref<Set<number>>(new Set());
  const entries = new Map<number, PollEntry>();

  const MAX_ATTEMPTS = 30;
  const MAX_DELAY_MS = 8000;

  function nextDelay(attempt: number): number {
    return Math.min(1000 * 2 ** attempt, MAX_DELAY_MS);
  }

  async function pollOne(fileId: number) {
    const entry = entries.get(fileId);
    if (!entry) return;

    try {
      const res = await fetchWithAuth(
        `${apiUrl}/api/assets/${fileId}/status`,
      );
      if (!res.ok) {
        // 404 means the file was deleted out from under us; stop polling.
        if (res.status === 404) {
          stopOne(fileId);
          return;
        }
        scheduleNext(entry);
        return;
      }
      const data = await res.json();
      const status: ProcessingStatus | undefined = data?.processingStatus;
      if (!status) {
        scheduleNext(entry);
        return;
      }
      const file = files.value.find((f) => f.id === fileId);
      if (file) {
        file.processingStatus = status;
      }
      if (TERMINAL_STATES.includes(status)) {
        stopOne(fileId);
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
      stopOne(entry.fileId);
      return;
    }
    entry.timer = setTimeout(() => pollOne(entry.fileId), nextDelay(entry.attempts));
  }

  function stopOne(fileId: number) {
    const e = entries.get(fileId);
    if (e?.timer) clearTimeout(e.timer);
    entries.delete(fileId);
    pending.value.delete(fileId);
    // Force reactivity on the Set ref.
    pending.value = new Set(pending.value);
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

  function stopAll() {
    for (const e of entries.values()) {
      if (e.timer) clearTimeout(e.timer);
    }
    entries.clear();
    pending.value = new Set();
  }

  return { pending, watchFiles, stopAll };
}
