<template>
  <div
    class="gallery-item"
    :draggable="isDraggable"
    :class="{ 'dragging': dragging, 'drag-over': dragOver }"
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
    <div
      class="image-container"
      @click="$emit('click', file)"
    >
      <img
        :src="thumbnailUrl"
        :alt="file.originalName"
        loading="lazy"
      >
      <div
        v-if="isVideoFile"
        class="video-play-overlay"
      >
        <span class="play-icon">▶</span>
      </div>
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
          v-if="!isVideoFile"
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
          🗑️ Delete
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
}

const props = withDefaults(defineProps<Props>(), {
  availableTags: () => [],
  isDraggable: false,
  showDragHandle: true,
  showFileInfo: true,
  dragging: false,
  dragOver: false
})

const emit = defineEmits<{
  click: [file: AlbumFile]
  delete: [fileId: number]
  rotate: [fileId: number]
  'add-tag': [fileId: number, tagName: string]
  'remove-tag': [fileId: number, tagName: string]
  'filter-tag': [tagName: string]
  'drag-start': [event: DragEvent]
  'drag-over': [event: DragEvent]
  'drag-enter': [event: DragEvent]
  'drag-leave': [event: DragEvent]
  drop: [event: DragEvent]
  'drag-end': [event: DragEvent]
}>()

const { getImageUrl } = useApi()

const thumbnailUrl = computed(() => getImageUrl(props.file, 'thumb'))
const isVideoFile = computed(() => isVideo(props.file))
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
