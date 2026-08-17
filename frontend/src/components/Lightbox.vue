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
  </div>
</template>

<script>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useApi } from '../composables/useApi'
import { isVideo } from '../utils/format'

export default {
  name: 'Lightbox',
  props: {
    file: {
      type: Object,
      default: null
    },
    isRecording: {
      type: Boolean,
      default: false
    },
    isSaving: {
      type: Boolean,
      default: false
    },
    isPlaying: {
      type: Boolean,
      default: false
    },
    isPaused: {
      type: Boolean,
      default: false
    },
    audioPlayer: {
      type: Object,
      default: null
    },
    // { id, label, text, position, total } for the current image, or null when it isn't in a
    // group. Cleared to null while the lightbox is closed, which also un-dismisses the hint.
    groupContext: {
      type: Object,
      default: null
    }
  },
  emits: ['close', 'next', 'previous', 'image-changed', 'pause-resume', 'stop-playback', 'update:controls-visible'],
  setup(props, { emit }) {
    const { getImageUrl } = useApi()
    const controlsVisible = ref(true)
    const isLoading = ref(false)
    const groupTextExpanded = ref(false)
    const groupHintDismissed = ref(false)

    const isVideoFile = computed(() => isVideo(props.file))

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
      return isVideoFile.value
        ? getImageUrl(props.file)
        : getImageUrl(props.file, 'large')
    })

    // Mute video when recording or playing slideshow audio
    const shouldMuteVideo = computed(() => {
      return props.isRecording || props.isPlaying
    })

    // Track when file changes to show loading state
    watch(() => props.file, (newFile, oldFile) => {
      if (newFile && oldFile && newFile.id !== oldFile.id) {
        isLoading.value = true
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

    function handleKeydown(event) {
      if (!props.file) return

      switch(event.key) {
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

    onMounted(() => {
      window.addEventListener('keydown', handleKeydown)
    })

    onUnmounted(() => {
      window.removeEventListener('keydown', handleKeydown)
    })

    return {
      isVideoFile,
      mediaUrl,
      controlsVisible,
      isLoading,
      shouldMuteVideo,
      groupHintVisible,
      groupTextExpanded,
      groupHintDismissed,
      toggleControls,
      handleImageLoad
    }
  }
}
</script>
