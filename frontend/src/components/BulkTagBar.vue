<template>
  <Teleport to="body">
    <Transition name="bulk-bar">
      <div
        v-if="selectedCount > 0"
        class="bulk-tag-bar"
        @keydown.esc.stop="$emit('clear')"
      >
        <span class="bulk-count">{{ selectedCount }} selected</span>

        <span
          v-if="busyLabel"
          class="bulk-busy"
        >{{ busyLabel }}</span>

        <div
          v-if="quickTags.length > 0"
          class="bulk-quick-tags"
        >
          <span class="bulk-label">Quick tag:</span>
          <button
            v-for="tag in quickTags"
            :key="tag.name"
            class="bulk-quick-btn"
            :disabled="busy"
            :title="`Tag all selected with &quot;${tag.name}&quot;`"
            @click="$emit('add-tag', tag.name)"
          >
            {{ tag.name }}
          </button>
        </div>

        <div class="bulk-custom-tag">
          <input
            ref="tagInput"
            v-model="customTag"
            class="bulk-tag-input"
            placeholder="Type or pick a tag…"
            list="bulk-tag-list"
            :disabled="busy"
            @keydown.enter.prevent="applyCustomTag"
            @keydown.esc.stop="clearCustomTag"
          >
          <datalist id="bulk-tag-list">
            <option
              v-for="tag in assignableTags(availableTags)"
              :key="tag.id"
              :value="tag.name"
            />
          </datalist>
          <button
            class="bulk-apply-btn"
            :disabled="busy || !customTag.trim()"
            @click="applyCustomTag"
          >
            Apply
          </button>
        </div>

        <div class="bulk-actions">
          <button
            class="bulk-action-btn"
            :disabled="busy || enhanceableCount === 0"
            :title="enhanceTitle"
            @click="$emit('enhance')"
          >
            <svg
              width="12"
              height="12"
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
            <span>{{ enhanceLabel }}</span>
          </button>
          <button
            class="bulk-action-btn"
            :disabled="busy || rotatableCount === 0"
            :title="rotateTitle"
            @click="$emit('rotate')"
          >
            <svg
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path d="M3 12a9 9 0 1 0 3-6.7" />
              <path d="M3 4v5h5" />
            </svg>
            <span>{{ rotateLabel }}</span>
          </button>
          <button
            class="bulk-action-btn bulk-action-danger"
            :disabled="busy"
            :title="`Delete ${selectedCount} selected file${selectedCount !== 1 ? 's' : ''}`"
            @click="$emit('delete-selected')"
          >
            <svg
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <polyline points="3 6 5 6 21 6" />
              <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a1 1 0 011-1h4a1 1 0 011 1v2" />
            </svg>
            <span>Delete</span>
          </button>
        </div>

        <button
          class="bulk-clear-btn"
          title="Clear selection (Esc)"
          @click="$emit('clear')"
        >
          <svg
            width="10"
            height="10"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
          >
            <path d="M18 6L6 18M6 6l12 12" />
          </svg>
          <span>Clear</span>
        </button>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { assignableTags } from '@/utils/tags'
import type { Tag, TagCount } from '@/types'

const props = defineProps<{
  selectedCount: number
  availableTags: Tag[]
  frequentTags: TagCount[]
  // Selected files the rotate job can act on — videos are excluded, so this can be 0 while
  // selectedCount is not.
  rotatableCount: number
  // Selected files the enhance job can act on: the rotatable ones minus those already enhanced
  // (D83). Always <= rotatableCount.
  enhanceableCount: number
  busy: boolean
  busyLabel: string
}>()

const emit = defineEmits<{
  'add-tag': [tagName: string]
  rotate: []
  enhance: []
  'delete-selected': []
  clear: []
}>()

const customTag = ref('')
const tagInput = ref<HTMLInputElement | null>(null)

// `hidden` is derived by the server (D79) and refused as an add, so it is not offered here.
// A typed "hidden" still goes through and comes back as "could not be tagged".
// Filter first, then decide whether to render the group at all — an album whose only tag is
// `hidden` would otherwise show a bare "Quick tag:" label with no buttons behind it.
const quickTags = computed(() => assignableTags(props.frequentTags))

// Only spell out the count when it differs from the selection — i.e. when videos were skipped.
const rotateLabel = computed(() =>
  props.rotatableCount === props.selectedCount
    ? 'Rotate'
    : `Rotate (${props.rotatableCount})`
)

const rotateTitle = computed(() =>
  props.rotatableCount === 0
    ? 'Videos cannot be rotated'
    : `Rotate ${props.rotatableCount} selected image${props.rotatableCount !== 1 ? 's' : ''} left 90°`
)

const enhanceLabel = computed(() =>
  props.enhanceableCount === props.selectedCount
    ? 'Enhance'
    : `Enhance (${props.enhanceableCount})`
)

// Three reasons the count can fall short of the selection, and the owner deserves to know which:
// videos have no enhance job, and an already-enhanced photo is skipped because a second pass
// compounds on the first with no way back (D83).
const enhanceTitle = computed(() => {
  const skippedVideos = props.selectedCount - props.rotatableCount
  const skippedEnhanced = props.rotatableCount - props.enhanceableCount
  if (props.enhanceableCount === 0) {
    if (props.rotatableCount === 0) return 'Videos cannot be enhanced'
    return 'Every selected image has already been enhanced'
  }
  const skipped = [
    skippedVideos > 0 ? `${skippedVideos} video${skippedVideos !== 1 ? 's' : ''}` : '',
    skippedEnhanced > 0 ? `${skippedEnhanced} already enhanced` : ''
  ].filter(Boolean)
  const suffix = skipped.length > 0 ? ` — skipping ${skipped.join(' and ')}` : ''
  return `Enhance colors, brightness and contrast of ${props.enhanceableCount} selected image${props.enhanceableCount !== 1 ? 's' : ''} (no preview)${suffix}`
})

function applyCustomTag() {
  const name = customTag.value.trim()
  if (name) {
    emit('add-tag', name)
    customTag.value = ''
  }
}

function clearCustomTag() {
  customTag.value = ''
}

defineExpose({ tagInput })
</script>
