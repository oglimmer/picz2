<template>
  <div class="album-gallery presentation-mode">
    <div class="gallery-header">
      <div class="gallery-nav">
        <h2>{{ album?.name || 'Loading...' }}</h2>
        <button
          class="subscribe-btn"
          @click="showSubscriptionDialog = true"
        >
          🔔 Notify me on updates
        </button>
      </div>
    </div>

    <!-- Presentation mode filter -->
    <div
      v-if="tagsUsedInAlbum.length > 1 || recordings.length > 0"
      class="controls presentation-controls"
    >
      <div
        v-if="tagsUsedInAlbum.length > 1"
        class="filter-controls"
      >
        <label for="tag-filter-presentation">Filter by tag:</label>
        <select
          id="tag-filter-presentation"
          v-model="selectedTag"
        >
          <option value="">
            Select a filter!
          </option>
          <option
            v-for="tag in tagsUsedInAlbum"
            :key="tag.name"
            :value="tag.name"
          >
            {{ tag.name }} ({{ tag.count }}){{ hasRecordings(tag.name) ? ' 🎵' : '' }}
          </option>
        </select>
        <span
          v-if="recordings.length > 0"
          class="audio-available-indicator"
        >AUDIO AVAILABLE</span>
      </div>
      <div
        v-if="!isPlaying"
        class="recording-controls"
      >
        <button
          v-if="hasRecordingForLanguage(selectedTag, 'language1')"
          class="play-btn"
          :title="`Play ${language1Name} recorded slideshow`"
          @click="handleStartPlayback('language1')"
        >
          ▶️ Play {{ language1Name }}
        </button>
        <button
          v-if="hasRecordingForLanguage(selectedTag, 'language2')"
          class="play-btn"
          :title="`Play ${language2Name} recorded slideshow`"
          @click="handleStartPlayback('language2')"
        >
          ▶️ Play {{ language2Name }}
        </button>
      </div>
    </div>

    <div
      v-if="loadingFiles"
      class="loading"
    >
      Loading photos...
    </div>

    <div
      v-else-if="files.length === 0"
      class="empty-state"
    >
      <h2>No photos in this album</h2>
    </div>

    <!-- Empty state when no filter selected (only show if multiple tags available) -->
    <div
      v-else-if="!selectedTag && tagsUsedInAlbum.length > 1"
      class="empty-state"
    >
      <h2>Please select a tag filter</h2>
      <p>Choose a tag from the dropdown above to view photos</p>
    </div>

    <!-- Gallery -->
    <div
      v-else
      class="gallery presentation-gallery"
    >
      <div
        v-for="file in files"
        :key="file.id"
        class="gallery-item"
        @click="openImage(file)"
      >
        <div class="image-container">
          <img
            :src="getThumbnailUrl(file)"
            :alt="file.originalName"
            loading="lazy"
          >
          <div
            v-if="isVideoFile(file)"
            class="video-play-overlay"
          >
            <span class="play-icon">▶</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Lightbox -->
    <Lightbox
      :file="selectedFile"
      :is-playing="isPlaying"
      :is-paused="isPaused"
      :audio-player="audioPlayer"
      @close="closeLightbox"
      @next="navigateNext"
      @previous="navigatePrevious"
      @pause-resume="handlePauseResume"
      @stop-playback="handleStopPlayback"
      @update:controls-visible="controlsVisible = $event"
    />

    <!-- Audio player overlay (shown on top of lightbox when playing) -->
    <div
      v-show="isPlaying && selectedFile"
      class="audio-overlay"
    >
      <audio
        ref="audioPlayer"
        controls
      />
    </div>

    <!-- Cookie Consent Banner -->
    <CookieConsent @consent="handleConsent" />

    <!-- Subscription Dialog -->
    <SubscriptionDialog
      :show="showSubscriptionDialog"
      :share-token="shareToken"
      :album-name="album?.name || 'this album'"
      :is-confirmation="isConfirmationMode"
      @close="showSubscriptionDialog = false"
      @subscribed="handleSubscribed"
    />
  </div>
</template>

<script>
import { ref, computed, watch, onMounted, nextTick } from 'vue'
import { useApi } from '../composables/useApi'
import { useSettings } from '../composables/useSettings'
import { useSlideshowPlayback } from '../composables/useSlideshowPlayback'
import { useNotifications } from '../composables/useNotifications'
import { useAnalytics } from '../composables/useAnalytics'
import { isVideo } from '../utils/format'
import Lightbox from '../components/Lightbox.vue'
import CookieConsent from '../components/CookieConsent.vue'
import SubscriptionDialog from '../components/SubscriptionDialog.vue'

export default {
  name: 'PublicGalleryView',
  components: {
    Lightbox,
    CookieConsent,
    SubscriptionDialog
  },
  props: {
    shareToken: {
      type: String,
      required: true
    },
    imageToken: {
      type: String,
      default: null
    },
    openLightbox: {
      type: Boolean,
      default: false
    }
  },
  setup(props) {
    const { apiUrl, getImageUrl, shareToken } = useApi()

    // Set the share token for API requests
    shareToken.value = props.shareToken

    const album = ref(null)
    const allFilesUnfiltered = ref([])
    const loadingFiles = ref(false)
    const selectedTag = ref('')
    const selectedFile = ref(null)
    const isInitialLoad = ref(true)

    // Language settings
    const { language1Name, language2Name, loadLanguageSettings } = useSettings()

    // Slideshow playback
    const {
      isPlaying,
      currentFile: playbackCurrentFile,
      recordings,
      loadRecordings,
      hasRecordings,
      startPlayback,
      stopPlayback,
      pausePlayback,
      resumePlayback
    } = useSlideshowPlayback()

    const { error, warning, info } = useNotifications()

    // Analytics - handle cookie consent for GDPR compliance
    const { hasConsent, consentGiven, logPageView, logFilterChange, logAudioPlay } = useAnalytics()

    // Track if consent choice has been made (to avoid duplicate page view logs)
    const consentChoiceMade = ref(false)

    const audioPlayer = ref(null)
    const isPaused = ref(false)
    const controlsVisible = ref(true)

    // Subscription dialog
    const showSubscriptionDialog = ref(false)
    const isConfirmationMode = ref(false)

    // Computed: Filtered files based on selected tag
    const files = computed(() => {
      if (!selectedTag.value) {
        return allFilesUnfiltered.value
      }
      return allFilesUnfiltered.value.filter(file =>
        file.tags && file.tags.includes(selectedTag.value)
      )
    })

    // Computed: Get tags actually used in files
    const tagsUsedInAlbum = computed(() => {
      if (!allFilesUnfiltered.value || allFilesUnfiltered.value.length === 0) return []

      const tagCounts = new Map()
      allFilesUnfiltered.value.forEach(file => {
        if (file.tags && Array.isArray(file.tags)) {
          file.tags.forEach(tag => {
            tagCounts.set(tag, (tagCounts.get(tag) || 0) + 1)
          })
        }
      })

      return Array.from(tagCounts.entries())
        .filter(([name]) => name !== 'no_tag')
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => a.name.localeCompare(b.name))
    })

    // Helper to check if recordings exist for a specific tag and language
    function hasRecordingForLanguage(tag, language) {
      // Normalize empty string to null for comparison
      const normalizedTag = tag || null
      return recordings.value.some(r => r.filterTag === normalizedTag && r.language === language)
    }

    // Helper to get recording for specific tag and language
    function getRecordingForLanguage(tag, language) {
      // Normalize empty string to null for comparison
      const normalizedTag = tag || null
      return recordings.value.find(r => r.filterTag === normalizedTag && r.language === language)
    }

    // Watch for playback current file changes and update lightbox
    watch(playbackCurrentFile, (newFile) => {
      if (isPlaying.value && newFile) {
        selectedFile.value = newFile
      }
    })

    // Watch for tag changes and send analytics (only for user-initiated changes)
    watch(selectedTag, async (newTag) => {
      // Don't track on initial load or when clearing the tag
      if (isInitialLoad.value || !newTag) {
        return
      }

      // Log filter change (will check consent internally)
      await logFilterChange(props.shareToken, newTag)
    })

    // Auto-select tag when there's only one tag
    watch(tagsUsedInAlbum, (tags) => {
      if (tags.length === 1) {
        selectedTag.value = tags[0].name
      }
    })

    onMounted(async () => {
      await loadAlbumInfo()
      await loadAlbumFiles()

      // Load language settings
      await loadLanguageSettings()

      // Load recordings for playback
      if (album.value) {
        await loadRecordings(album.value.id)
      }

      // If imageToken is provided, open that specific image
      if (props.openLightbox && props.imageToken) {
        const file = files.value.find(f => f.publicToken === props.imageToken)
        if (file) {
          selectedFile.value = file
        }
      }

      // After initial load and auto-selection, mark as ready for analytics tracking
      await nextTick()
      isInitialLoad.value = false

      // Check if user already made a consent choice (returning visitor)
      // If yes, log page view now. If no, wait for user to make choice in handleConsent()
      if (hasConsentCookie()) {
        consentChoiceMade.value = true
        await logPageView(props.shareToken, selectedTag.value || undefined)
      }
    })

    function hasConsentCookie() {
      const cookies = document.cookie.split(';')
      for (const cookie of cookies) {
        const [name] = cookie.trim().split('=')
        if (name === 'cookie_consent') {
          return true
        }
      }
      return false
    }

    async function loadAlbumInfo() {
      try {
        const response = await fetch(`${apiUrl}/api/albums/public/${props.shareToken}`)
        const data = await response.json()

        if (data.success && data.album) {
          album.value = data.album
        }
      } catch (err) {
        console.error('Error loading album:', err)
      }
    }

    async function loadAlbumFiles() {
      loadingFiles.value = true

      try {
        const url = `${apiUrl}/api/albums/public/${props.shareToken}/files`
        const response = await fetch(url)
        const data = await response.json()

        if (data.success) {
          allFilesUnfiltered.value = data.files || []
        }
      } catch (err) {
        console.error('Error loading files:', err)
      } finally {
        loadingFiles.value = false
      }
    }

    function getThumbnailUrl(file) {
      return getImageUrl(file, 'thumb')
    }

    function isVideoFile(file) {
      return isVideo(file)
    }

    function openImage(file) {
      selectedFile.value = file
    }

    function closeLightbox() {
      // Stop audio playback when closing the lightbox
      if (isPlaying.value) {
        stopPlayback()
        controlsVisible.value = true
      }
      selectedFile.value = null
    }

    function navigateNext() {
      if (!selectedFile.value || files.value.length === 0) return

      const currentIndex = files.value.findIndex(f => f.id === selectedFile.value.id)
      if (currentIndex === -1) return

      // Show hint when wrapping from last to first
      if (currentIndex === files.value.length - 1) {
        info('Starting over')
      }

      const nextIndex = (currentIndex + 1) % files.value.length
      selectedFile.value = files.value[nextIndex]
    }

    function navigatePrevious() {
      if (!selectedFile.value || files.value.length === 0) return

      const currentIndex = files.value.findIndex(f => f.id === selectedFile.value.id)
      if (currentIndex === -1) return

      // Show hint when wrapping from first to last
      if (currentIndex === 0) {
        info('Jumped to the end')
      }

      const previousIndex = (currentIndex - 1 + files.value.length) % files.value.length
      selectedFile.value = files.value[previousIndex]
    }

    // Slideshow Playback
    async function handleStartPlayback(language) {
      if (files.value.length === 0) {
        warning('No images available to play')
        return
      }

      try {
        // Get recording for this tag and language
        const recording = getRecordingForLanguage(selectedTag.value, language)

        if (!recording) {
          warning('No recording found for this filter and language')
          return
        }

        // Log audio play analytics (will check consent internally)
        await logAudioPlay(props.shareToken, recording.id, selectedTag.value || undefined)

        // Start playback - pass audio element ref
        await startPlayback(recording, files.value, audioPlayer.value)
        isPaused.value = false
        controlsVisible.value = true

        // Open lightbox with first image
        if (playbackCurrentFile.value) {
          selectedFile.value = playbackCurrentFile.value
        }
      } catch (err) {
        console.error('Failed to start playback:', err)
        error('Failed to start playback: ' + err.message)
      }
    }

    function handlePauseResume() {
      if (isPaused.value) {
        resumePlayback()
        isPaused.value = false
      } else {
        pausePlayback()
        isPaused.value = true
      }
    }

    function handleStopPlayback() {
      stopPlayback()
      isPaused.value = false
      controlsVisible.value = true
      selectedFile.value = null
    }

    async function handleConsent(accepted) {
      consentGiven(accepted)

      // After user makes consent choice, log the page view
      // Will use visitor_id cookie if accepted, fallback hash if declined
      if (!consentChoiceMade.value) {
        consentChoiceMade.value = true
        await logPageView(props.shareToken, selectedTag.value || undefined)
      }
    }

    function handleSubscribed() {
      info('Subscription created! Please check your email to confirm.')
    }

    return {
      album,
      files,
      loadingFiles,
      selectedTag,
      tagsUsedInAlbum,
      selectedFile,
      isPlaying,
      isPaused,
      recordings,
      hasRecordings,
      hasRecordingForLanguage,
      language1Name,
      language2Name,
      audioPlayer,
      showSubscriptionDialog,
      isConfirmationMode,
      getThumbnailUrl,
      isVideoFile,
      openImage,
      closeLightbox,
      navigateNext,
      navigatePrevious,
      handleStartPlayback,
      handlePauseResume,
      handleStopPlayback,
      handleConsent,
      handleSubscribed
    }
  }
}
</script>

<style scoped>
.gallery-nav {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 16px;
}

.subscribe-btn {
  padding: 10px 20px;
  background-color: #4CAF50;
  color: white;
  border: none;
  border-radius: 4px;
  font-size: 0.95rem;
  cursor: pointer;
  transition: all 0.2s;
  white-space: nowrap;
}

.subscribe-btn:hover {
  background-color: #45a049;
  transform: translateY(-1px);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
}

.subscribe-btn:active {
  transform: translateY(0);
}
</style>
