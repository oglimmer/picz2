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
    </div>
    <button
      v-if="selectable && !bulkSelect"
      class="select-checkbox"
      :class="{ 'is-checked': selected }"
      :title="selected ? 'Deselect' : 'Select (Shift+click for range)'"
      @click.stop="(e) => $emit('toggle-select', file.id, e.shiftKey)"
    >
      <svg
        v-if="selected"
        class="checkbox-icon"
        width="11"
        height="11"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="3"
      >
        <path d="M20 6L9 17l-5-5" />
      </svg>
    </button>

    <div
      class="image-container"
      @click="(e) => selectionActive ? $emit('toggle-select', file.id, e.shiftKey) : $emit('click', file)"
    >
      <LazyImage
        v-if="thumbnailReady"
        :src="thumbnailUrl"
        :alt="file.originalName"
      />
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
        <svg
          class="play-icon"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="currentColor"
        >
          <path d="M8 5v14l11-7z" />
        </svg>
      </div>
      <!-- D83: enhance rewrites the stored original and compounds on itself, so the one photo it
           already ran on has to look different from the ones it has not. -->
      <span
        v-if="file.enhancedAt"
        class="enhanced-badge"
        :title="enhancedTitle"
      >
        <svg
          width="10"
          height="10"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M15 4l1.2 2.8L19 8l-2.8 1.2L15 12l-1.2-2.8L11 8l2.8-1.2z" />
          <path d="M6 12l.9 2.1L9 15l-2.1.9L6 18l-.9-2.1L3 15l2.1-.9z" />
          <path d="M18 15l.6 1.4L20 17l-1.4.6L18 19l-.6-1.4L16 17l1.4-.6z" />
        </svg>
        <span>Enhanced</span>
      </span>
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
      <div
        v-if="showFileInfo"
        class="item-actions"
        @click.stop
      >
        <button
          v-if="!isVideoFile && canRotate"
          class="tile-btn"
          :title="file.enhancedAt ? enhancedTitle : 'Enhance colors, brightness and contrast'"
          @click.stop="$emit('enhance', file.id)"
        >
          <svg
            width="13"
            height="13"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="M15 4l1.2 2.8L19 8l-2.8 1.2L15 12l-1.2-2.8L11 8l2.8-1.2z" />
            <path d="M6 12l.9 2.1L9 15l-2.1.9L6 18l-.9-2.1L3 15l2.1-.9z" />
            <path d="M18 15l.6 1.4L20 17l-1.4.6L18 19l-.6-1.4L16 17l1.4-.6z" />
          </svg>
        </button>
        <button
          v-if="!isVideoFile && canRotate"
          class="tile-btn"
          title="Rotate left 90°"
          @click.stop="$emit('rotate', file.id)"
        >
          <svg
            width="13"
            height="13"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M3 12a9 9 0 1 0 3-6.7" />
            <path d="M3 4v5h5" />
          </svg>
        </button>
        <button
          class="tile-btn tile-btn--danger"
          title="Delete photo"
          @click.stop="$emit('delete', file.id)"
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
      <button
        v-if="moveTarget"
        class="move-here-btn"
        title="Move selected images here"
        @click.stop="$emit('move-here', file.id)"
      >
        <svg
          width="11"
          height="11"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
        >
          <path d="M12 5v14M19 12l-7 7-7-7" />
        </svg>
        <span>Move here</span>
      </button>
      <span
        v-if="groupStart"
        class="group-start-badge"
        title="A group starts at this photo"
      >Group start</span>
      <span
        v-if="groupEnd"
        class="group-end-badge"
        title="The group stops after this photo"
      >Group end</span>
      <span
        v-if="groupEnd"
        class="group-end-edge"
        aria-hidden="true"
      />
      <div
        v-if="(canStartGroup && !groupStart) || canEndGroup"
        class="group-marker-actions"
      >
        <button
          v-if="canStartGroup && !groupStart"
          class="start-group-btn"
          title="Start a new group at this photo"
          @click.stop="$emit('start-group', file.id)"
        >
          Start group
        </button>
        <button
          v-if="canEndGroup"
          class="start-group-btn"
          :title="groupEnd
            ? 'Let the group run on to the next one again'
            : 'Stop the group after this photo'"
          @click.stop="$emit('end-group', file.id)"
        >
          {{ groupEnd ? 'Reopen group' : 'End group here' }}
        </button>
      </div>
    </div>
    <!-- The owner's caption (D69). Outside `file-info` on purpose: that block is owner-only
         chrome, while the caption is written for the readers and has to survive presentation
         mode, where showFileInfo is false. -->
    <p
      v-if="file.caption && !editingCaption"
      class="file-caption"
      :title="file.caption"
      @click.stop
    >
      {{ file.caption }}
    </p>
    <div
      v-if="showFileInfo"
      class="file-info"
    >
      <div class="file-name">
        {{ file.originalName }}
      </div>
      <!-- When a photo carries its own date, that is the one worth showing; the upload
           date stays available on hover rather than taking a second line on every tile. -->
      <div class="file-meta">
        <span class="file-size">{{ fileSize }}</span>
        <span
          v-if="exifDate"
          class="file-exif-date"
          :title="uploadedTitle"
        >Taken {{ exifDate }}</span>
        <span
          v-else-if="fileDate"
          class="file-date"
        >{{ fileDate }}</span>
      </div>
      <div class="file-tags">
        <span
          v-for="tag in file.tags"
          :key="tag"
          class="tag"
          :title="isAssignableTag(tag) ? undefined : 'Hidden until you give this photo a tag'"
          @click.stop="$emit('filter-tag', tag)"
        >
          {{ tag }}
          <!-- `hidden` has no ×: it comes straight back on a photo with no other tag (D79), so
               the way out is the "+ Add tag" select, not this button. -->
          <button
            v-if="isAssignableTag(tag)"
            class="tag-remove"
            title="Remove tag"
            @click.stop="$emit('remove-tag', file.id, tag)"
          >&times;</button>
        </span>
      </div>
      <div
        v-if="editingCaption"
        class="caption-editor"
        @click.stop
      >
        <textarea
          ref="captionInput"
          v-model="captionDraft"
          class="caption-input"
          rows="3"
          :maxlength="MAX_CAPTION_LENGTH"
          placeholder="Say something about this photo…"
          @keydown.esc.stop="cancelCaption"
          @keydown.enter.meta.prevent="saveCaption"
          @keydown.enter.ctrl.prevent="saveCaption"
        />
        <div class="caption-editor-actions">
          <button
            class="caption-btn caption-btn--save"
            @click.stop="saveCaption"
          >
            Save
          </button>
          <button
            class="caption-btn"
            @click.stop="cancelCaption"
          >
            Cancel
          </button>
        </div>
      </div>
      <div class="file-actions">
        <button
          class="caption-toggle"
          :title="file.caption ? 'Edit caption' : 'Add a caption'"
          @click.stop="startEditingCaption"
        >
          {{ file.caption ? 'Edit caption' : '+ Add caption' }}
        </button>
        <select
          class="tag-select"
          :value="''"
          aria-label="Add a tag to this photo"
          @change="handleAddTag"
          @click.stop
        >
          <option value="">
            + Add tag
          </option>
          <option
            v-for="tag in assignableTags(availableTags)"
            :key="tag.id"
            :value="tag.name"
            :disabled="file.tags && file.tags.includes(tag.name)"
          >
            {{ tag.name }}
          </option>
        </select>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import LazyImage from '@/components/LazyImage.vue'
import { useApi } from '@/composables/useApi'
import { formatBytes, formatDate, isVideo } from '@/utils/format'
import { assignableTags, isAssignableTag } from '@/utils/tags'
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
  /** Presentation mode, logged in: offer "start a group at this photo". */
  canStartGroup?: boolean
  /** This photo is already the anchor of a group — show a marker instead of the button. */
  groupStart?: boolean
  /** This photo sits inside a group, so it can be made that group's last photo. */
  canEndGroup?: boolean
  /** This photo is already where its group stops — the button reopens the group instead. */
  groupEnd?: boolean
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
  moveTarget: false,
  canStartGroup: false,
  groupStart: false,
  canEndGroup: false,
  groupEnd: false
})

const emit = defineEmits<{
  click: [file: AlbumFile]
  delete: [fileId: number]
  rotate: [fileId: number]
  enhance: [fileId: number]
  'add-tag': [fileId: number, tagName: string]
  'update-caption': [fileId: number, caption: string]
  'remove-tag': [fileId: number, tagName: string]
  'filter-tag': [tagName: string]
  'toggle-select': [fileId: number, shiftKey?: boolean]
  'move-here': [fileId: number]
  'start-group': [fileId: number]
  'end-group': [fileId: number]
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
    case 'DEAD_LETTER':
      return 'Failed'
    default:
      return 'Processing…'
  }
})
const processingTitle = computed(() => {
  switch (props.file.processingStatus) {
    case 'DEAD_LETTER':
      return 'Processing failed permanently'
    default:
      return 'Generating thumbnail…'
  }
})
const isVideoFile = computed(() => isVideo(props.file))
// Rotation and enhancement work even on assets whose original has been purged by retention — the
// worker falls back to the largest available derivative (output is bounded by LARGE=2400px
// regardless), so neither button is gated on originalAvailable. The flag is kept on FileInfo for
// any future "download original" UI but does not affect either job.
const canRotate = computed(() => true)
const fileSize = computed(() => formatBytes(props.file.size))
const fileDate = computed(() => formatDate(props.file.uploadedAt))
const exifDate = computed(() => props.file.exifDateTimeOriginal ? formatDate(props.file.exifDateTimeOriginal) : null)
const uploadedTitle = computed(() => fileDate.value ? `Uploaded ${fileDate.value}` : '')

// D83. Serves both the corner badge and the tile button, so the same sentence explains the mark
// and warns the finger that is about to run it a second time.
const enhancedTitle = computed(() => {
  const when = props.file.enhancedAt ? formatDate(props.file.enhancedAt) : ''
  return `Already enhanced${when ? ` (${when})` : ''} — enhancing again builds on that result`
})

// Mirrors MAX_CAPTION_LENGTH in FileStorageService — the textarea stops typing at the same
// point the server would reject, so nobody writes a paragraph and loses it on Save.
const MAX_CAPTION_LENGTH = 2000

const editingCaption = ref(false)
const captionDraft = ref('')
const captionInput = ref<HTMLTextAreaElement | null>(null)

function startEditingCaption() {
  captionDraft.value = props.file.caption ?? ''
  editingCaption.value = true
  nextTick(() => captionInput.value?.focus())
}

function cancelCaption() {
  editingCaption.value = false
}

/** Emitting a blank caption is how the caption is cleared — the server stores null for it. */
function saveCaption() {
  emit('update-caption', props.file.id, captionDraft.value.trim())
  editingCaption.value = false
}

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
