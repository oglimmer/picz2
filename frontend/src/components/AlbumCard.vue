<template>
  <div
    class="album-tile"
    :style="{ '--i': tileIndex }"
    @click="$emit('click')"
  >
    <div class="tile-frame">
      <img
        v-if="album.coverImageToken"
        :src="coverUrl"
        :alt="album.name"
        class="tile-image"
      >
      <div
        v-else
        class="tile-placeholder"
      >
        <div class="placeholder-crosshair">
          <span class="ch-h" />
          <span class="ch-v" />
          <span class="ch-corner ch-corner--tl" />
          <span class="ch-corner ch-corner--tr" />
          <span class="ch-corner ch-corner--bl" />
          <span class="ch-corner ch-corner--br" />
        </div>
        <span class="placeholder-label">Empty</span>
      </div>

      <div class="tile-caption">
        <span class="tile-frame-count">
          {{ album.fileCount || 0 }}&nbsp;{{ (album.fileCount || 0) === 1 ? 'frame' : 'frames' }}
        </span>
        <h3 class="tile-title">
          {{ album.name }}
        </h3>
        <p
          v-if="album.description"
          class="tile-desc"
        >
          {{ album.description }}
        </p>
      </div>

      <div
        class="tile-actions"
        @click.stop
      >
        <button
          v-if="canDuplicate"
          class="tile-btn"
          title="Duplicate album"
          @click.stop="$emit('duplicate', album.id)"
        >
          <svg
            width="13"
            height="13"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <rect
              x="9"
              y="9"
              width="13"
              height="13"
              rx="2"
              ry="2"
            />
            <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
          </svg>
        </button>
        <button
          v-if="canDelete"
          class="tile-btn tile-btn--danger"
          title="Delete album"
          @click.stop="$emit('delete', album.id)"
        >
          <svg
            width="13"
            height="13"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <polyline points="3 6 5 6 21 6" />
            <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a1 1 0 011-1h4a1 1 0 011 1v2" />
          </svg>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useApi } from '@/composables/useApi'
import type { Album } from '@/types'

interface Props {
  album: Album
  canDelete?: boolean
  canDuplicate?: boolean
  tileIndex?: number
}

const props = withDefaults(defineProps<Props>(), {
  canDelete: false,
  canDuplicate: false,
  tileIndex: 0
})

defineEmits<{
  click: []
  delete: [albumId: number]
  duplicate: [albumId: number]
}>()

const { getAlbumCoverUrl } = useApi()
const coverUrl = computed(() => getAlbumCoverUrl(props.album))
</script>
