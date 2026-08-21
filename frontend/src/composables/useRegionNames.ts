import { ref, type Ref } from "vue";
import { getApiUrl } from "../utils/api-config";
import { useCapabilities } from "./useCapabilities";
import type { LatLng } from "../utils/dayRegionGrouping";
import { formatCoordinates } from "../utils/dayRegionGrouping";

/**
 * Puts a place name on a region cluster ("Munich", "Sankt Peter-Ording") by asking our own
 * `/api/geocode/reverse`, which answers from its cache and only falls through to Apple for a
 * coordinate nobody has ever asked about.
 *
 * <p>Deliberately not MapKit's browser-side geocoder: that pulls the whole MapKit bundle into a
 * page that may never show a map, re-asks Apple once per visitor because the browser cache is
 * per-person, and spends the quota on every reload. One shared server-side cache costs one lookup
 * per place, ever.
 *
 * This is decoration, never data. Coordinates are rendered the moment a label is asked for and a
 * name replaces them if one arrives; an unreachable server, a throttled endpoint or an install
 * with no Apple credentials all leave the coordinates standing.
 */

/** Matches the server's snapping (degrees × 10^4), so both sides agree on what "same spot" means. */
function cacheKey(at: LatLng): string {
  return `${at.lat.toFixed(4)},${at.lng.toFixed(4)}`;
}

// Module-scoped: names are page-wide, so switching albums or toggling the grouping off and on
// never re-asks for a place already known.
const cache = new Map<string, string>();
const pending = new Map<string, LatLng>();
const asked = new Set<string>();

// Bumped whenever names land, so labels rendered from this module re-evaluate.
const version: Ref<number> = ref(0);

/** Server cap (`maps.geocode.max-points-per-request`); larger batches are split. */
const MAX_POINTS_PER_REQUEST = 60;

/**
 * How long to collect misses before sending. A grouped album renders every heading in one frame,
 * so a short wait turns twenty requests into one; long enough to catch a slow list, short enough
 * that nobody sees coordinates flicker into names.
 */
const BATCH_DELAY_MS = 50;

/** After a 429 or a network error, stop asking for this long rather than hammering. */
const BACKOFF_MS = 60_000;

let flushTimer: ReturnType<typeof setTimeout> | null = null;
let backoffUntil = 0;

let geocodingEnabled: boolean | null = null;
let capabilityCheck: Promise<boolean> | null = null;

/** Whether this install can name coordinates at all — decided once per page. */
function ensureGeocodingEnabled(): Promise<boolean> {
  if (geocodingEnabled !== null) return Promise.resolve(geocodingEnabled);
  if (!capabilityCheck) {
    const { ensureLoaded } = useCapabilities();
    capabilityCheck = ensureLoaded()
      .then((caps) => {
        geocodingEnabled = Boolean(caps.maps?.geocoding);
        return geocodingEnabled;
      })
      .catch(() => {
        geocodingEnabled = false;
        return false;
      });
  }
  return capabilityCheck;
}

function scheduleFlush(): void {
  if (flushTimer !== null) return;
  flushTimer = setTimeout(() => {
    flushTimer = null;
    void flush();
  }, BATCH_DELAY_MS);
}

async function flush(): Promise<void> {
  if (pending.size === 0) return;
  if (Date.now() < backoffUntil) {
    pending.clear();
    return;
  }
  if (!(await ensureGeocodingEnabled())) {
    pending.clear();
    return;
  }

  const batch = Array.from(pending.entries()).slice(0, MAX_POINTS_PER_REQUEST);
  for (const [key] of batch) pending.delete(key);
  // Anything over the cap goes out in the next batch rather than being dropped.
  if (pending.size > 0) scheduleFlush();

  const params = new URLSearchParams();
  for (const [, at] of batch) params.append("loc", `${at.lat.toFixed(4)},${at.lng.toFixed(4)}`);
  params.set("lang", navigator.language || "en");

  try {
    const response = await fetch(`${getApiUrl()}/api/geocode/reverse?${params.toString()}`);
    if (!response.ok) {
      // 429 means we asked too often; anything else is the server having a bad day. Either way,
      // waiting is the only sensible response, and the coordinates on screen stay correct.
      backoffUntil = Date.now() + BACKOFF_MS;
      for (const [key] of batch) asked.delete(key);
      return;
    }
    const data: { places?: { lat: number; lng: number; name: string | null }[] } =
      await response.json();
    let landed = 0;
    for (const place of data.places || []) {
      const key = cacheKey({ lat: place.lat, lng: place.lng });
      if (place.name) {
        cache.set(key, place.name);
        landed++;
      } else {
        // The server knows of no name *yet* — it may still be resolving in the background — so the
        // key is left askable rather than cached as empty.
        asked.delete(key);
      }
    }
    if (landed > 0) version.value++;
  } catch {
    backoffUntil = Date.now() + BACKOFF_MS;
    for (const [key] of batch) asked.delete(key);
  }
}

export function useRegionNames() {
  /**
   * The name for a cluster centre if one is known, else null. Queues the coordinate for the next
   * batched request the first time it is seen, so calling this from a template is safe.
   */
  function regionName(at: LatLng | null): string | null {
    if (!at) return null;
    // Read `version` unconditionally: a label that only touched it on a miss would stop tracking
    // it as soon as it had a name, and miss later arrivals for other clusters.
    void version.value;
    const key = cacheKey(at);
    const known = cache.get(key);
    if (known) return known;
    if (!asked.has(key)) {
      asked.add(key);
      pending.set(key, at);
      scheduleFlush();
    }
    return null;
  }

  /** What to print above a region: its place name, or its coordinates until one arrives. */
  function regionLabel(at: LatLng | null): string {
    if (!at) return "No location";
    return regionName(at) || formatCoordinates(at);
  }

  return { regionName, regionLabel };
}
