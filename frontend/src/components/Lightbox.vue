<template>
  <div
    v-if="file"
    class="lightbox"
    @click="$emit('close')"
  >
    <span class="close-lightbox">&times;</span>
    <!-- Which group this photo belongs to. Most viewing happens zoomed in, so the section
         heading has to follow the reader in here or they never see it. -->
    <div
      v-if="groupContext && groupHintVisible"
      class="group-hint"
      title="Hide — reappears at the next group"
      @click.stop="groupHintDismissed = true"
    >
      <div class="group-hint-head">
        <span class="group-hint-label">{{ groupContext.label }}</span>
        <span class="group-hint-count">{{ groupContext.position }} / {{ groupContext.total }}</span>
      </div>
      <p
        v-if="groupContext.text"
        class="group-hint-text"
        :class="{ 'group-hint-text--clamped': !groupTextExpanded }"
      >
        {{ groupContext.text }}
      </p>
      <button
        v-if="groupContext.text"
        class="group-hint-toggle"
        @click.stop="groupTextExpanded = !groupTextExpanded"
      >
        {{ groupTextExpanded ? 'Show less' : 'Show more' }}
      </button>
    </div>
    <div
      v-if="isRecording || isSaving"
      class="recording-overlay"
    >
      <span
        v-if="isSaving"
        class="recording-indicator-lightbox saving"
      >💾 Saving recording…</span>
      <span
        v-else
        class="recording-indicator-lightbox"
      >🔴 REC</span>
    </div>
    <div
      v-if="isPlaying && controlsVisible"
      class="playback-overlay"
      @click.stop
    >
      <div class="playback-controls">
        <button
          class="pause-resume-btn"
          @click="$emit('pause-resume')"
        >
          {{ isPaused ? '▶️ Resume' : '⏸️ Pause' }}
        </button>
        <button
          class="stop-playback-btn"
          @click="$emit('stop-playback')"
        >
          ⏹️ Stop
        </button>
        <button
          class="hide-controls-btn"
          @click="toggleControls"
        >
          👁️ Hide Controls
        </button>
      </div>
    </div>
    <div
      v-if="isPlaying && !controlsVisible"
      class="show-controls-overlay"
      @click.stop
    >
      <button
        class="show-controls-btn"
        @click="toggleControls"
      >
        👁️ Show Controls
      </button>
    </div>
    <div
      v-if="isLoading && !isVideoFile"
      class="loading-indicator"
    >
      <div class="spinner" />
    </div>
    <video
      v-if="isVideoFile"
      :src="mediaUrl"
      :muted="shouldMuteVideo"
      controls
      autoplay
      @click.stop
      @loadeddata="handleImageLoad"
    />
    <img
      v-else
      :src="mediaUrl"
      :alt="file.originalName"
      @click.stop="$emit('next')"
      @load="handleImageLoad"
      @error="handleImageLoad"
    >
    <!-- The owner's caption (D69). Sits over the bottom of the frame so it reads as part of the
         photo, and hides with the rest of the chrome during slideshow playback. Clamped to three
         lines with a toggle, like the group hint above: a long caption left to run free would
         climb the frame and cover the photo it describes. -->
    <div
      v-if="file.caption && captionVisible"
      class="lightbox-caption"
      @click.stop
    >
      <p
        class="lightbox-caption-text"
        :class="{ 'lightbox-caption-text--clamped': !captionExpanded }"
      >
        {{ file.caption }}
      </p>
      <button
        v-if="captionIsLong"
        class="lightbox-caption-toggle"
        @click.stop="captionExpanded = !captionExpanded"
      >
        {{ captionExpanded ? 'Show less' : 'Show more' }}
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useApi } from '@/composables/useApi'
import { isVideo } from '@/utils/format'
import type { AlbumFile } from '@/types'
import type { GroupContext } from '@/composables/usePresentationGroups'

interface Props {
  file: AlbumFile | null
  isRecording?: boolean
  isSaving?: boolean
  isPlaying?: boolean
  isPaused?: boolean
  // Which group the current image sits in, or null when it is in none. Cleared to null while the
  // lightbox is closed, which also un-dismisses the hint.
  groupContext?: GroupContext | null
}

const props = withDefaults(defineProps<Props>(), {
  isRecording: false,
  isSaving: false,
  isPlaying: false,
  isPaused: false,
  groupContext: null
})

const emit = defineEmits<{
  close: []
  next: []
  previous: []
  'pause-resume': []
  'stop-playback': []
  'update:controls-visible': [visible: boolean]
}>()

const { getImageUrl } = useApi()
const controlsVisible = ref(true)
const isLoading = ref(false)
const groupTextExpanded = ref(false)
const captionExpanded = ref(false)
const groupHintDismissed = ref(false)

const isVideoFile = computed(() => (props.file ? isVideo(props.file) : false))

// Whether the toggle is worth drawing at all. A character count rather than a measured height:
// the plate's width varies with the viewport, so any exact answer would need a resize observer
// to stay right, and being one line out here costs nothing — the toggle simply appears on a
// caption that turns out to fit.
const captionIsLong = computed(() => (props.file?.caption?.length ?? 0) > 140)

// The caption is chrome, so "Hide Controls" hides it too, and it stays out of the way while a
// recording is being made.
const captionVisible = computed(
  () => !props.isRecording && !props.isSaving && (!props.isPlaying || controlsVisible.value)
)

// Stays out of the way of the REC badge (same corner) and honours "Hide Controls" during
// slideshow playback, so the photo can still be seen unobstructed.
const groupHintVisible = computed(
  () =>
    !groupHintDismissed.value &&
    !props.isRecording &&
    !props.isSaving &&
    (!props.isPlaying || controlsVisible.value)
)

const mediaUrl = computed(() => {
  if (!props.file) return ''
  return isVideoFile.value ? getImageUrl(props.file) : getImageUrl(props.file, 'large')
})

// Mute video when recording or playing slideshow audio
const shouldMuteVideo = computed(() => props.isRecording || props.isPlaying)

// Track when file changes to show loading state
watch(() => props.file, (newFile, oldFile) => {
  if (newFile && oldFile && newFile.id !== oldFile.id) {
    isLoading.value = true
    // A caption belongs to its photo, so an expanded one must not stay expanded over the
    // next photo's — the reader would meet a wall of text they never asked to unfold.
    captionExpanded.value = false
  }
})

// Moving into a different group is a fresh chapter: bring a dismissed hint back and collapse
// the blurb again, so a long text doesn't stay expanded over the next photos. Keyed on the
// group id rather than the label, because two groups may legitimately share a label.
watch(() => props.groupContext?.id, () => {
  groupTextExpanded.value = false
  groupHintDismissed.value = false
})

function handleImageLoad() {
  isLoading.value = false
}

function toggleControls() {
  controlsVisible.value = !controlsVisible.value
  emit('update:controls-visible', controlsVisible.value)
}

function handleKeydown(event: KeyboardEvent) {
  if (!props.file) return
  switch (event.key) {
    case 'Escape':
      emit('close')
      break
    case 'ArrowLeft':
      emit('previous')
      break
    case 'ArrowRight':
      emit('next')
      break
  }
}

onMounted(() => window.addEventListener('keydown', handleKeydown))
onUnmounted(() => window.removeEventListener('keydown', handleKeydown))
</script>
