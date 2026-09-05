import { ref, type Ref } from "vue";
import type { Capabilities } from "@/types";
import { getApiUrl } from "../utils/api-config";

// Module-scoped cache: capabilities only change at server-deploy boundaries, so a single
// load-and-keep is enough. We don't bother with a TTL — a hard refresh of the SPA picks up
// any new value, which lines up with how we deploy.
const cached = ref<Capabilities | null>(null);
const inflight = ref<Promise<Capabilities> | null>(null);

export interface CapabilitiesComposable {
  capabilities: Ref<Capabilities | null>;
  ensureLoaded: () => Promise<Capabilities>;
}

/**
 * Phase 5 — fetch and cache /api/capabilities. The composable returns the cached value
 * synchronously after the first load; callers that need a guaranteed-loaded value should
 * await {@link ensureLoaded}.
 */
export function useCapabilities(): CapabilitiesComposable {
  async function ensureLoaded(): Promise<Capabilities> {
    if (cached.value) return cached.value;
    if (inflight.value) return inflight.value;

    const apiUrl = getApiUrl();
    inflight.value = fetch(`${apiUrl}/api/capabilities`)
      .then(async (res) => {
        if (!res.ok) {
          throw new Error(`capabilities HTTP ${res.status}`);
        }
        const json = (await res.json()) as Capabilities;
        cached.value = json;
        return json;
      })
      .catch((err) => {
        // Hand the caller a safe fallback for *this* call, but leave `cached` empty so the next
        // call asks the server again. Caching the fallback would turn one network blip into a
        // map and a TUS path that stay hidden until a hard refresh.
        console.warn("Capabilities fetch failed, falling back to multipart:", err);
        const fallback: Capabilities = {
          tus: { enabled: false, endpoint: "/files/", version: "1.0.0", maxSize: 0 },
          multipart: { enabled: true, endpoint: "/api/upload" },
          maps: { enabled: false, geocoding: false },
        };
        return fallback;
      })
      .finally(() => {
        inflight.value = null;
      });

    return inflight.value;
  }

  return { capabilities: cached, ensureLoaded };
}
