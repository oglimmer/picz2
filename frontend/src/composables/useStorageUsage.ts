import { ref, computed, type Ref, type ComputedRef } from "vue";
import { useApi } from "./useApi";
import type { StorageUsage } from "@/types";

// Module singleton (see composables/README.md): whether the account's storage on this site is
// full is one fact about the signed-in user, and the banner that shows it lives in App.vue while
// the things that change it — uploads, deletes — happen inside views.
const usage = ref<StorageUsage | null>(null);
let inflight: Promise<void> | null = null;
let timer: ReturnType<typeof setInterval> | null = null;

/**
 * A change on the server is reflected here at the latest after this. Uploads and deletes call
 * {@link refresh} themselves, so the timer only covers what happened elsewhere — the iOS app
 * filling the last megabytes, the operator raising the quota with SQL.
 */
export const STORAGE_USAGE_POLL_MS = 60_000;

export interface StorageUsageComposable {
  usage: Ref<StorageUsage | null>;
  /** True exactly while uploads to the site's own storage are refused. */
  storageFull: ComputedRef<boolean>;
  refresh: () => Promise<void>;
  startPolling: () => void;
  stopPolling: () => void;
}

/**
 * The signed-in user's standing with the site's own storage, for the persistent "storage full"
 * banner. The server decides `full` — the same rule the upload path enforces — so this never
 * compares the two numbers itself.
 */
export function useStorageUsage(): StorageUsageComposable {
  const { apiUrl, requestJson } = useApi();

  const storageFull = computed(() => usage.value?.full === true);

  async function refresh(): Promise<void> {
    if (inflight) return inflight;
    inflight = requestJson<StorageUsage>(`${apiUrl}/api/storage-usage`)
      .then((data) => {
        usage.value = data;
      })
      .catch((err) => {
        // Keep the last answer. A network blip must not take a true warning down, and an
        // unknown state must not put one up — the next poll asks again.
        console.warn("Storage usage fetch failed:", err);
      })
      .finally(() => {
        inflight = null;
      });
    return inflight;
  }

  function startPolling(): void {
    if (timer) return;
    void refresh();
    timer = setInterval(() => void refresh(), STORAGE_USAGE_POLL_MS);
    if (typeof document !== "undefined") {
      document.addEventListener("visibilitychange", onVisible);
    }
  }

  function stopPolling(): void {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    if (typeof document !== "undefined") {
      document.removeEventListener("visibilitychange", onVisible);
    }
    usage.value = null;
  }

  function onVisible(): void {
    // A tab that was in the background for an hour has a stale answer; ask on the way back.
    if (document.visibilityState === "visible") void refresh();
  }

  return { usage, storageFull, refresh, startPolling, stopPolling };
}
