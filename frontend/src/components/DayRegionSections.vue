<template>
  <div class="day-groups">
    <section
      v-for="day in groups"
      :key="day.key"
      class="day-group"
    >
      <header class="day-group-header">
        <h2 class="day-group-title">
          {{ formatDayLabel(day) }}
        </h2>
        <span class="day-group-count">{{ day.count }} {{ day.count === 1 ? 'photo' : 'photos' }}</span>
      </header>

      <div
        v-for="cluster in day.clusters"
        :key="cluster.key"
        class="region-group"
      >
        <div class="region-header">
          <span class="region-name">
            <svg
              v-if="cluster.located"
              class="region-icon"
              width="11"
              height="11"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z" />
              <circle
                cx="12"
                cy="10"
                r="3"
              />
            </svg>
            {{ regionLabel(cluster.center) }}
          </span>
          <span class="region-meta">
            {{ cluster.files.length }} {{ cluster.files.length === 1 ? 'photo' : 'photos' }}<template
              v-if="cluster.located && cluster.spreadMeters > 0"
            > · within {{ formatDistance(cluster.spreadMeters) }}</template>
          </span>
        </div>
        <div
          class="gallery"
          :class="gridClass"
        >
          <template
            v-for="file in cluster.files"
            :key="`${file.id}:${file.publicToken}`"
          >
            <slot :file="file" />
          </template>
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { useRegionNames } from '@/composables/useRegionNames'
import { formatDayLabel, formatDistance, type DayGroup } from '@/utils/dayRegionGrouping'

/**
 * The "by day and region" shelving: one section per calendar day, one sub-section per place. The
 * caller decides what a photo looks like through the default slot, so the owner's gallery can hand
 * in its full tile and the public page its read-only one over the same headings.
 */
interface Props {
  groups: DayGroup[]
  /** Extra class on each photo grid, e.g. the thumbnail size or the presentation variant. */
  gridClass?: string
}

withDefaults(defineProps<Props>(), { gridClass: '' })

defineSlots<{
  default(props: { file: import('@/types').AlbumFile }): unknown
}>()

// Place names for the region headings; coordinates stand in until (or unless) one arrives.
const { regionLabel } = useRegionNames()
</script>
