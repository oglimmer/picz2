<template>
  <div
    class="gallery-item"
    :draggable="isDraggable && !selectionActive"
    :class="{ 'dragging': dragging, 'drag-over': dragOver, 'selected': selected }"
    @dragstart="handleDragStart"
    @dragover.prevent="handleDragOver"
    @dragenter="handleDragEnter"
    @dragleave="handleDragLeave"
    @drop="handleDrop"
    @dragend="handleDragEnd"
  >
    <div
      v-if="showDragHandle"
      class="drag-handle"
      title="Drag to reorder"
    >
      ⋮⋮
    </div>
    <button
      v-if="selectable && !bulkSelect"
      class="select-checkbox"
      :class="{ 'is-checked': selected }"
      :title="selected ? 'Deselect' : 'Select (Shift+click for range)'"
      @click.stop="(e) => $emit('toggle-select', file.id, e.shiftKey)"
    >
      <span class="checkbox-icon">{{ selected ? '✓' : '' }}</span>
    </button>

    <div
      class="image-container"
      @click="(e) => selectionActive ? $emit('toggle-select', file.id, e.shiftKey) : $emit('click', file)"
    >
      <img
        v-if="thumbnailReady"
        :src="thumbnailUrl"
        :alt="file.originalName"
        loading="lazy"
      >
      <div
        v-else
        class="processing-placeholder"
        :title="processingTitle"
      >
        <span class="processing-spinner" />
        <span class="processing-label">{{ processingLabel }}</span>
      </div>
      <div
        v-if="isVideoFile"
        class="video-play-overlay"
      >
        <span class="play-icon">▶</span>
      </div>
      <label
        v-if="bulkSelect"
        class="select-checkbox-overlay"
        :class="{ 'select-checkbox-overlay-reorder': selectVariant === 'reorder' }"
        :title="selected ? 'Deselect' : 'Select'"
        @click.stop
      >
        <input
          type="checkbox"
          :checked="selected"
          @change="$emit('toggle-select', file.id)"
        >
      </label>
      <button
        v-if="moveTarget"
        class="move-here-btn"
        title="Move selected images here"
        @click.stop="$emit('move-here', file.id)"
      >
        ⬇ Move here
      </button>
    </div>
    <div
      v-if="showFileInfo"
      class="file-info"
    >
      <div class="file-name">
        {{ file.originalName }}
      </div>
      <div class="file-meta">
        <span class="file-size">{{ fileSize }}</span>
        <span class="file-date">{{ fileDate }}</span>
        <span
          v-if="exifDate"
          class="file-exif-date"
          title="EXIF DateTimeOriginal"
        >📷 {{ exifDate }}</span>
      </div>
      <div class="file-tags">
        <span
          v-for="tag in file.tags"
          :key="tag"
          class="tag"
          @click.stop="$emit('filter-tag', tag)"
        >
          {{ tag }}
          <button
            class="tag-remove"
            title="Remove tag"
            @click.stop="$emit('remove-tag', file.id, tag)"
          >&times;</button>
        </span>
      </div>
      <div class="file-actions">
        <select
          class="tag-select"
          :value="''"
          @change="handleAddTag"
          @click.stop
        >
          <option value="">
            + Add tag
          </option>
          <option
            v-for="tag in availableTags"
            :key="tag.id"
            :value="tag.name"
            :disabled="file.tags && file.tags.includes(tag.name)"
          >
            {{ tag.name }}
          </option>
        </select>
        <button
          v-if="!isVideoFile && canRotate"
          class="rotate-btn"
          title="Rotate left 90°"
          @click.stop="$emit('rotate', file.id)"
        >
          ↻
        </button>
        <button
          class="delete-btn"
          title="Delete photo"
          @click.stop="$emit('delete', file.id)"
        >
          🗑️
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useApi } from '@/composables/useApi'
import { formatBytes, formatDate, isVideo } from '@/utils/format'
import type { AlbumFile, Tag } from '@/types'

interface Props {
  file: AlbumFile
  availableTags?: Tag[]
  isDraggable?: boolean
  showDragHandle?: boolean
  showFileInfo?: boolean
  dragging?: boolean
  dragOver?: boolean
  selectable?: boolean
  selected?: boolean
  selectionActive?: boolean
  bulkSelect?: boolean
  selectVariant?: 'delete' | 'reorder'
  moveTarget?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  availableTags: () => [],
  isDraggable: false,
  showDragHandle: true,
  showFileInfo: true,
  dragging: false,
  dragOver: false,
  selectable: false,
  selected: false,
  selectionActive: false,
  bulkSelect: false,
  selectVariant: 'delete',
  moveTarget: false
})

const emit = defineEmits<{
  click: [file: AlbumFile]
  delete: [fileId: number]
  rotate: [fileId: number]
  'add-tag': [fileId: number, tagName: string]
  'remove-tag': [fileId: number, tagName: string]
  'filter-tag': [tagName: string]
  'toggle-select': [fileId: number, shiftKey?: boolean]
  'move-here': [fileId: number]
  'drag-start': [event: DragEvent]
  'drag-over': [event: DragEvent]
  'drag-enter': [event: DragEvent]
  'drag-leave': [event: DragEvent]
  drop: [event: DragEvent]
  'drag-end': [event: DragEvent]
}>()

const { getImageUrl } = useApi()

// Treat absent processingStatus (older rows pre-Gap 6) as DONE so we don't suppress them.
const thumbnailReady = computed(
  () => !props.file.processingStatus || props.file.processingStatus === 'DONE'
)
const thumbnailUrl = computed(() => getImageUrl(props.file, 'thumb'))
const processingLabel = computed(() => {
  switch (props.file.processingStatus) {
    case 'FAILED':
    case 'DEAD_LETTER':
      return 'Failed'
    default:
      return 'Processing…'
  }
})
const processingTitle = computed(() => {
  switch (props.file.processingStatus) {
    case 'FAILED':
      return 'Processing failed — will retry'
    case 'DEAD_LETTER':
      return 'Processing failed permanently'
    default:
      return 'Generating thumbnail…'
  }
})
const isVideoFile = computed(() => isVideo(props.file))
// Rotation needs the original bytes; once retention has purged the original
// (originalAvailable === false) the rotate button is hidden. Treat undefined as available so
// older list responses (pre-Phase-6 backend) keep showing the button.
const canRotate = computed(() => props.file.originalAvailable !== false)
const fileSize = computed(() => formatBytes(props.file.size))
const fileDate = computed(() => formatDate(props.file.uploadedAt))
const exifDate = computed(() => props.file.exifDateTimeOriginal ? formatDate(props.file.exifDateTimeOriginal) : null)

function handleAddTag(event: Event) {
  const target = event.target as HTMLSelectElement
  const tagName = target.value
  if (tagName) {
    emit('add-tag', props.file.id, tagName)
    target.value = ''
  }
}

function handleDragStart(event: DragEvent) {
  emit('drag-start', event)
}

function handleDragOver(event: DragEvent) {
  emit('drag-over', event)
}

function handleDragEnter(event: DragEvent) {
  emit('drag-enter', event)
}

function handleDragLeave(event: DragEvent) {
  emit('drag-leave', event)
}

function handleDrop(event: DragEvent) {
  emit('drop', event)
}

function handleDragEnd(event: DragEvent) {
  emit('drag-end', event)
}
</script>
