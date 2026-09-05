import { computed, ref, watch, type ComputedRef, type Ref } from "vue";
import {
  DEFAULT_REGION_RADIUS_METERS,
  groupByDayAndRegion,
  type DayGroup,
} from "../utils/dayRegionGrouping";
import type { AlbumFile } from "@/types";

export interface DayRegionView {
  dayRegionGrouping: Ref<boolean>;
  dayRegionAvailable: ComputedRef<boolean>;
  dayRegionActive: ComputedRef<boolean>;
  dayRegionGroups: ComputedRef<DayGroup[]>;
}

/**
 * "By day and region": a second reading of the same photos — day sections, each cut into places at
 * most 2 km across (see utils/dayRegionGrouping.ts).
 *
 * <p>Only offered once a tag is chosen: day sections over every photo an album holds are as long
 * as the album and say nothing. Always starts off and is never remembered across visits — the plain
 * grid is what a gallery is, and a setting from some earlier session silently re-shelving it would
 * be a worse surprise than one click.
 *
 * @param files the filtered set to group
 * @param available the extra gates (a tag is selected, the map is not open, not playing…)
 */
export function useDayRegionView(
  files: Ref<AlbumFile[]>,
  available: () => boolean,
): DayRegionView {
  const dayRegionGrouping = ref(false);
  const dayRegionAvailable = computed(available);
  const dayRegionActive = computed(() => dayRegionAvailable.value && dayRegionGrouping.value);

  // Losing the tag drops grouping too, so the control never claims a mode the page is not in.
  watch(dayRegionAvailable, (ok) => {
    if (!ok) dayRegionGrouping.value = false;
  });

  const dayRegionGroups = computed(() =>
    dayRegionActive.value ? groupByDayAndRegion(files.value, DEFAULT_REGION_RADIUS_METERS) : [],
  );

  return { dayRegionGrouping, dayRegionAvailable, dayRegionActive, dayRegionGroups };
}
