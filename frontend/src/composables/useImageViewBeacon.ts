import { onMounted, onUnmounted } from "vue";
import { useApi } from "./useApi";
import { isTextCard } from "../utils/format";
import type { AlbumFile } from "@/types";

/** One photo's pile since the last send, in the shape the server reads (D90). */
export interface ImageViewEntry {
  fileId: number;
  opens: number;
  walkIns: number;
}

export interface ImageViewBatcher {
  /** The visitor clicked the photo in the grid or on the map. */
  recordOpen: (file: AlbumFile) => void;
  /** The visitor reached the photo with next/previous while already full screen. */
  recordWalkIn: (file: AlbumFile) => void;
  /** Hands everything counted so far to `send` and starts a fresh pile. */
  flush: () => void;
  /** How many photos are waiting. */
  size: () => number;
}

/** The server drops anything past 200 photos in one batch; sending early keeps us under that. */
export const MAX_BATCH_ENTRIES = 200;

/**
 * The counting half of the per-photo beacon, with no timers or page events — those are the
 * composable's job — so it can be tested on its own.
 *
 * Looks are added up here and sent as one batch, not as one request per arrow press: a visitor
 * walking through an album full screen would otherwise fire a request a second. A text card is
 * never counted; it has no picture to look at (D86).
 */
export function createImageViewBatcher(
  send: (entries: ImageViewEntry[]) => void,
  maxEntries = MAX_BATCH_ENTRIES,
): ImageViewBatcher {
  let pending = new Map<number, ImageViewEntry>();

  function bump(file: AlbumFile, field: "opens" | "walkIns"): void {
    if (!file || isTextCard(file)) return;
    let entry = pending.get(file.id);
    if (!entry) {
      entry = { fileId: file.id, opens: 0, walkIns: 0 };
      pending.set(file.id, entry);
    }
    entry[field] += 1;
    if (pending.size >= maxEntries) flush();
  }

  function flush(): void {
    if (pending.size === 0) return;
    const entries = [...pending.values()];
    pending = new Map();
    send(entries);
  }

  return {
    recordOpen: (file) => bump(file, "opens"),
    recordWalkIn: (file) => bump(file, "walkIns"),
    flush,
    size: () => pending.size,
  };
}

/** A pile waiting this long goes out even if the visitor is still looking. */
const FLUSH_INTERVAL_MS = 30_000;

/**
 * Counts which photos a visitor of the share page looks at full screen, and sends the counts.
 *
 * Sent when the lightbox closes (the caller calls `flush`), when the tab is hidden or the page is
 * left, and every 30 seconds otherwise. The request is `keepalive`, so it still goes out while the
 * page unloads — the moment most piles are complete. A lost batch is only lost counts; nothing
 * here retries or ever shows an error.
 */
export function useImageViewBeacon(shareToken: () => string): ImageViewBatcher {
  const { apiUrl } = useApi();

  const batcher = createImageViewBatcher((views) => {
    try {
      void fetch(`${apiUrl}/api/albums/public/${shareToken()}/analytics/image-views`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ views }),
        credentials: "include",
        keepalive: true,
      }).catch(() => {
        // Analytics must never break the page.
      });
    } catch {
      // Same: a browser that refuses the request is not the visitor's problem.
    }
  });

  let timer: ReturnType<typeof setInterval> | undefined;

  function onVisibilityChange(): void {
    if (document.visibilityState === "hidden") batcher.flush();
  }

  onMounted(() => {
    document.addEventListener("visibilitychange", onVisibilityChange);
    window.addEventListener("pagehide", batcher.flush);
    timer = setInterval(batcher.flush, FLUSH_INTERVAL_MS);
  });

  onUnmounted(() => {
    document.removeEventListener("visibilitychange", onVisibilityChange);
    window.removeEventListener("pagehide", batcher.flush);
    clearInterval(timer);
    // Leaving the share page inside the app, not closing the tab: send what is left.
    batcher.flush();
  });

  return batcher;
}
