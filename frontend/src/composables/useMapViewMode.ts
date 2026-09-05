import { computed, ref, watch, type ComputedRef, type Ref } from "vue";
import { useCapabilities } from "./useCapabilities";
import type { AlbumFile } from "@/types";

export interface MapViewMode {
  mapMode: Ref<boolean>;
  mapFilterAvailable: ComputedRef<boolean>;
}

/**
 * Whether the map view can be offered at all, and whether it is on.
 *
 * <p>The map is a *view*, not a tag: it is deliberately kept out of `selectedTag`, which feeds
 * recordings, presentation groups and analytics — a sentinel string leaking into any of those
 * would be a silent data bug. It needs the server to have Apple Maps configured, and it needs at
 * least one located photo, because an album with none would open an empty world map.
 *
 * @param files every file of the album (not the filtered set — the map shows the whole album)
 * @param enabled an extra gate, e.g. "not in presentation mode"
 */
export function useMapViewMode(
  files: Ref<AlbumFile[]>,
  enabled: () => boolean = () => true,
): MapViewMode {
  const mapMode = ref(false);
  const mapsEnabled = ref(false);

  useCapabilities()
    .ensureLoaded()
    .then((caps) => {
      mapsEnabled.value = Boolean(caps.maps?.enabled);
    })
    .catch(() => {
      mapsEnabled.value = false;
    });

  const hasLocatedFiles = computed(() =>
    files.value.some(
      (f) => typeof f.gpsLatitude === "number" && typeof f.gpsLongitude === "number",
    ),
  );

  const mapFilterAvailable = computed(() => enabled() && mapsEnabled.value && hasLocatedFiles.value);

  // An album can lose its located photos (last one deleted) while the map is open.
  watch(mapFilterAvailable, (available) => {
    if (!available) mapMode.value = false;
  });

  return { mapMode, mapFilterAvailable };
}
