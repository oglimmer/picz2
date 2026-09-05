<template>
  <div class="grid-size-picker">
    <button
      v-for="size in SIZES"
      :key="size"
      class="grid-size-btn"
      :class="{ 'grid-size-btn--active': modelValue === size }"
      :title="`${size.charAt(0).toUpperCase() + size.slice(1)} thumbnails`"
      :aria-pressed="modelValue === size"
      @click="$emit('update:modelValue', size)"
    >
      <svg
        v-if="size === 'small'"
        width="14"
        height="14"
        viewBox="0 0 14 14"
        fill="currentColor"
      >
        <rect
          x="0"
          y="0"
          width="6"
          height="6"
          rx="1"
        />
        <rect
          x="8"
          y="0"
          width="6"
          height="6"
          rx="1"
        />
        <rect
          x="0"
          y="8"
          width="6"
          height="6"
          rx="1"
        />
        <rect
          x="8"
          y="8"
          width="6"
          height="6"
          rx="1"
        />
      </svg>
      <svg
        v-else-if="size === 'medium'"
        width="14"
        height="14"
        viewBox="0 0 14 14"
        fill="currentColor"
      >
        <rect
          x="0"
          y="0"
          width="6"
          height="14"
          rx="1"
        />
        <rect
          x="8"
          y="0"
          width="6"
          height="14"
          rx="1"
        />
      </svg>
      <svg
        v-else
        width="14"
        height="14"
        viewBox="0 0 14 14"
        fill="currentColor"
      >
        <rect
          x="0"
          y="0"
          width="14"
          height="14"
          rx="1"
        />
      </svg>
    </button>
  </div>
</template>

<script setup lang="ts">
export type GridSize = 'small' | 'medium' | 'large'

/** The three-step thumbnail size switch over the album shelf and over an album's photos (D67). */
defineProps<{ modelValue: GridSize }>()
defineEmits<{ 'update:modelValue': [size: GridSize] }>()

const SIZES: GridSize[] = ['small', 'medium', 'large']
</script>
