<template>
  <div
    class="album-tile"
    :class="{ dragging, 'drag-over': dragOver }"
    :style="{ '--i': tileIndex }"
    :draggable="isDraggable"
    @click="$emit('click')"
    @dragstart="$emit('drag-start', $event)"
    @dragover.prevent="$emit('drag-over', $event)"
    @dragenter="$emit('drag-enter', $event)"
    @drop="$emit('drop', $event)"
    @dragend="$emit('drag-end', $event)"
  >
    <div class="tile-frame">
      <!-- The tile itself is the drag handle; the grip only says so. Kept out of the pointer's
           way so a click on it still opens the album. -->
      <span
        v-if="isDraggable"
        class="tile-grip"
        title="Drag to reorder"
        aria-hidden="true"
      >
        <svg
          width="10"
          height="14"
          viewBox="0 0 10 14"
          fill="currentColor"
        >
          <circle
            cx="2.5"
            cy="2.5"
            r="1.2"
          />
          <circle
            cx="7.5"
            cy="2.5"
            r="1.2"
          />
          <circle
            cx="2.5"
            cy="7"
            r="1.2"
          />
          <circle
            cx="7.5"
            cy="7"
            r="1.2"
          />
          <circle
            cx="2.5"
            cy="11.5"
            r="1.2"
          />
          <circle
            cx="7.5"
            cy="11.5"
            r="1.2"
          />
        </svg>
      </span>

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

      <!-- An unpublished album is only visible to its owner. Saying so on the tile is the
           difference between a deliberate draft and a share link the owner thinks is working. -->
      <span
        v-if="album.published === false"
        class="tile-private"
        title="Not shared. Open the album and turn on Public sharing."
      >
        Private
      </span>

      <!-- Ties the masthead's "phone uploads to X" line to the tile it means. -->
      <span
        v-if="isUploadTarget"
        class="tile-destination"
        title="Your phone is uploading into this album"
      >
        <span class="receiving-dot receiving-dot--live" />
        <span class="tile-destination-label">Receiving</span>
      </span>

      <div class="tile-caption">
        <span class="tile-frame-count">
          {{ (album.fileCount || 0).toLocaleString() }}&nbsp;{{ (album.fileCount || 0) === 1 ? 'frame' : 'frames' }}
          <!-- Nested inside the frame count on purpose: the small grid already hides that
               element, and a third-width tile has no room for a second meta line. -->
          <span
            v-if="coverDate"
            class="tile-cover-date"
          >{{ coverDate }}</span>
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
          :disabled="isDeleting"
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
          :disabled="isDeleting"
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

      <!-- Deletion overlay -->
      <div
        v-if="isDeleting"
        class="tile-deleting-overlay"
        @click.stop
      >
        <svg
          class="tile-deleting-spinner"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
        >
          <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
        </svg>
        <span class="tile-deleting-label">Deleting…</span>
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
  isDeleting?: boolean
  isUploadTarget?: boolean
  /** The owner may drag this tile to put the shelf in a different order. */
  isDraggable?: boolean
  /** This tile is the one being dragged. */
  dragging?: boolean
  /** The dragged tile would land here. */
  dragOver?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  canDelete: false,
  canDuplicate: false,
  tileIndex: 0,
  isDeleting: false,
  isUploadTarget: false,
  isDraggable: false,
  dragging: false,
  dragOver: false
})

defineEmits<{
  click: []
  delete: [albumId: number]
  duplicate: [albumId: number]
  'drag-start': [event: DragEvent]
  'drag-over': [event: DragEvent]
  'drag-enter': [event: DragEvent]
  drop: [event: DragEvent]
  'drag-end': [event: DragEvent]
}>()

const { getAlbumCoverUrl } = useApi()
const coverUrl = computed(() => getAlbumCoverUrl(props.album))

/**
 * When the album's first photo was taken, as a plain local date.
 *
 * Deliberately not `formatDate`: "Today" and "3 days ago" are right for a single photo's meta
 * line, but an album is a place, and a bare date is what tells the owner which trip a tile is.
 * An unparseable or missing value renders nothing and the element is dropped.
 */
const coverDate = computed(() => {
  if (!props.album.coverImageDate) return ''
  const date = new Date(props.album.coverImageDate)
  if (Number.isNaN(date.getTime())) return ''
  return date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
})
</script>

<style scoped>
/* Sits behind a hairline divider rather than on its own line, so the caption keeps
   the same height whether or not the album holds a photo. */
.tile-cover-date::before {
  content: '\00b7';
  margin: 0 0.4em;
  opacity: 0.6;
}

.tile-deleting-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border-radius: inherit;
  z-index: 10;
  pointer-events: all;
}

.tile-deleting-spinner {
  width: 28px;
  height: 28px;
  color: #fff;
  animation: spin 1s linear infinite;
}

.tile-deleting-label {
  font-size: 0.75rem;
  color: #fff;
  letter-spacing: 0.05em;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
