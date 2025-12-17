<template>
  <div
    v-if="file"
    class="lightbox"
    @click="$emit('close')"
  >
    <span class="close-lightbox">&times;</span>
    <div
      v-if="isRecording"
      class="recording-overlay"
    >
      <span class="recording-indicator-lightbox">🔴 REC</span>
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
    }
  },
  emits: ['close', 'next', 'previous', 'image-changed', 'pause-resume', 'stop-playback', 'update:controls-visible'],
  setup(props, { emit }) {
    const { getImageUrl } = useApi()
    const controlsVisible = ref(true)
    const isLoading = ref(false)

    const isVideoFile = computed(() => isVideo(props.file))

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
      toggleControls,
      handleImageLoad
    }
  }
}
</script>
