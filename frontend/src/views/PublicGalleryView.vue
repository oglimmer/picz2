<template>
  <!-- An unpublished (or deleted) album answers 404 on every public route. Without this the
       visitor got an empty gallery under a "Loading..." heading and no idea why. -->
  <div
    v-if="albumUnavailable"
    class="album-gallery presentation-mode"
  >
    <div class="gallery-header">
      <div class="gallery-nav">
        <h2>Album not available</h2>
      </div>
    </div>
    <p class="album-unavailable-text">
      This link does not open an album. It may not be shared yet, or it may have been removed.
      Ask whoever sent it to you to check.
    </p>
  </div>

  <div
    v-else
    class="album-gallery presentation-mode"
    :class="{ 'map-mode': mapMode }"
  >
    <div
      ref="galleryTop"
      class="gallery-header"
      tabindex="-1"
    >
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
      v-if="tagsUsedInAlbum.length > 1 || recordings.length > 0 || mapFilterAvailable || dayRegionAvailable"
      class="controls presentation-controls"
    >
      <div
        v-if="tagsUsedInAlbum.length > 1 || mapFilterAvailable"
        class="filter-controls"
      >
        <label for="tag-filter-presentation">Filter by tag:</label>
        <select
          id="tag-filter-presentation"
          v-model="filterSelection"
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
          <option
            v-if="mapFilterAvailable"
            :value="MAP_FILTER_VALUE"
          >
            🗺️ Map
          </option>
        </select>
        <span
          v-if="recordings.length > 0"
          class="audio-available-indicator"
        >AUDIO AVAILABLE</span>
      </div>
      <label
        v-if="dayRegionAvailable && !isPlaying"
        class="day-region-toggle"
        :class="{ 'day-region-toggle--active': dayRegionGrouping }"
        title="Group these photos by the day they were taken, then by places within 2 km of each other"
      >
        <input
          v-model="dayRegionGrouping"
          type="checkbox"
        >
        <span>📅 By day &amp; region</span>
      </label>
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
      <div class="empty-inner">
        <p class="empty-title">
          No photos in this album
        </p>
      </div>
    </div>

    <!-- Map filter: replaces the grid. Fed every file in the album, since the map is an
         alternative to tag filtering rather than something layered on top of it. -->
    <PhotoMap
      v-else-if="mapMode"
      :files="allFilesUnfiltered"
      :saved-view="albumMapViewValue"
      @open="openImage"
    />

    <!-- By day & region: day sections, each cut into places at most 2 km across. Only reachable
         with a tag selected, so it never stands in for the "pick a tag" prompt below. -->
    <div
      v-else-if="dayRegionActive"
      class="day-groups"
    >
      <section
        v-for="day in dayRegionGroups"
        :key="day.key"
        class="day-group"
      >
        <header class="day-group-header">
          <h2 class="day-group-title">
            {{ formatDayLabel(day) }}
          </h2>
          <span class="day-group-count">{{ day.count }} {{ day.count === 1 ? 'photo' : 'photos' }}</span>
        </header>

        <div
          v-for="cluster in day.clusters"
          :key="cluster.key"
          class="region-group"
        >
          <div class="region-header">
            <span class="region-name">
              <svg
                v-if="cluster.located"
                class="region-icon"
                width="11"
                height="11"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
              >
                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z" />
                <circle
                  cx="12"
                  cy="10"
                  r="3"
                />
              </svg>
              {{ regionLabel(cluster.center) }}
            </span>
            <span class="region-meta">
              {{ cluster.files.length }} {{ cluster.files.length === 1 ? 'photo' : 'photos' }}<template
                v-if="cluster.located && cluster.spreadMeters > 0"
              > · within {{ formatDistance(cluster.spreadMeters) }}</template>
            </span>
          </div>
          <div class="gallery presentation-gallery">
            <div
              v-for="file in cluster.files"
              :key="file.id"
              class="gallery-item"
              @click="openImage(file)"
            >
              <div class="image-container">
                <LazyImage
                  :src="getThumbnailUrl(file)"
                  :alt="file.originalName"
                />
                <div
                  v-if="isVideoFile(file)"
                  class="video-play-overlay"
                >
                  <span class="play-icon">▶</span>
                </div>
              </div>
              <!-- The owner's caption (D69), read-only here. -->
              <p
                v-if="file.caption"
                class="file-caption"
                :title="file.caption"
              >
                {{ file.caption }}
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>

    <!-- Empty state when no filter selected (only show if multiple tags available) -->
    <div
      v-else-if="!selectedTag && tagsUsedInAlbum.length > 1"
      class="empty-state"
    >
      <div class="empty-inner">
        <p class="empty-title">
          Please select a tag filter
        </p>
        <p class="empty-hint">
          Choose a tag from the dropdown above to view photos
        </p>
      </div>
    </div>

    <!-- Gallery, split into image groups (per tag) -->
    <div
      v-else
      class="presentation-sections"
    >
      <section
        v-for="section in presentationSections"
        :key="section.group ? `group-${section.group.id}` : 'lead'"
        class="presentation-section"
        :class="{ 'presentation-section--lead': !section.group }"
      >
        <PresentationGroupHeader
          v-if="section.group"
          :group="section.group"
          :count="section.files.length"
        />
        <div class="gallery presentation-gallery">
          <div
            v-for="file in section.files"
            :key="file.id"
            class="gallery-item"
            @click="openImage(file)"
          >
            <div class="image-container">
              <LazyImage
                :src="getThumbnailUrl(file)"
                :alt="file.originalName"
              />
              <div
                v-if="isVideoFile(file)"
                class="video-play-overlay"
              >
                <span class="play-icon">▶</span>
              </div>
            </div>
            <!-- The owner's caption (D69), read-only here. -->
            <p
              v-if="file.caption"
              class="file-caption"
              :title="file.caption"
            >
              {{ file.caption }}
            </p>
          </div>
        </div>
      </section>
    </div>

    <!-- Lightbox -->
    <Lightbox
      :file="selectedFile"
      :group-context="lightboxGroupContext"
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

    <!-- Back to top: floating button whose ring shows how far the page is scrolled -->
    <Transition name="back-to-top">
      <button
        v-show="showBackToTop"
        type="button"
        class="back-to-top-btn"
        :aria-label="`Back to top — ${scrollProgress}% of the page scrolled`"
        title="Back to top"
        @click="scrollToTop"
      >
        <svg
          class="back-to-top-ring"
          viewBox="0 0 44 44"
          aria-hidden="true"
        >
          <circle
            class="back-to-top-ring-track"
            cx="22"
            cy="22"
            r="20"
          />
          <circle
            class="back-to-top-ring-progress"
            cx="22"
            cy="22"
            r="20"
            :stroke-dasharray="RING_CIRCUMFERENCE"
            :stroke-dashoffset="ringOffset"
          />
        </svg>
        <svg
          class="back-to-top-icon"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path d="M12 19V5M5 12l7-7 7 7" />
        </svg>
      </button>
    </Transition>

    <!-- Cookie Consent Banner -->
    <CookieConsent @consent="handleConsent" />

    <!-- Subscription Dialog -->
    <SubscriptionDialog
      :show="showSubscriptionDialog"
      :share-token="shareToken"
      :album-name="album?.name || 'this album'"
      :is-confirmation="isConfirmationMode"
      @close="showSubscriptionDialog = false"
    />
  </div>
</template>

<script>
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue'
import { useApi } from '../composables/useApi'
import { useSettings } from '../composables/useSettings'
import { useSlideshowPlayback } from '../composables/useSlideshowPlayback'
import { useNotifications } from '../composables/useNotifications'
import { useAnalytics } from '../composables/useAnalytics'
import { usePresentationGroups } from '../composables/usePresentationGroups'
import { isVideo } from '../utils/format'
import { groupByDayAndRegion, formatDayLabel, formatDistance, DEFAULT_REGION_RADIUS_METERS } from '../utils/dayRegionGrouping'
import { useRegionNames } from '../composables/useRegionNames'
import { albumMapView } from '../types'
import Lightbox from '../components/Lightbox.vue'
import LazyImage from '../components/LazyImage.vue'
import CookieConsent from '../components/CookieConsent.vue'
import SubscriptionDialog from '../components/SubscriptionDialog.vue'
import PresentationGroupHeader from '../components/PresentationGroupHeader.vue'
import PhotoMap from '../components/PhotoMap.vue'
import { useCapabilities } from '../composables/useCapabilities'

export default {
  name: 'PublicGalleryView',
  components: {
    Lightbox,
    LazyImage,
    CookieConsent,
    SubscriptionDialog,
    PresentationGroupHeader,
    PhotoMap
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
    // Set when the public album endpoint answers 404: not shared, removed, or never existed.
    const albumUnavailable = ref(false)
    // The owner's saved framing for the map filter, if they set one. Read-only here: a share-link
    // visitor can pan and zoom all they like, but nothing they do is persisted.
    const albumMapViewValue = computed(() => albumMapView(album.value))
    // Never offered as a filter and never counted: an asset carrying it is dropped on arrival.
    const HIDDEN_TAG = 'hidden'
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

    // Presentation image groups (read-only here)
    const { loadPublicGroups, buildSections, groupContextFor } = usePresentationGroups()

    const { error, warning, info } = useNotifications()

    // Analytics - handle cookie consent for GDPR compliance
    const { hasConsent, consentGiven, logPageView, logFilterChange, logAudioPlay } = useAnalytics()

    // Track if consent choice has been made (to avoid duplicate page view logs)
    const consentChoiceMade = ref(false)

    const audioPlayer = ref(null)
    const isPaused = ref(false)
    const controlsVisible = ref(true)
    const showBackToTop = ref(false)
    const scrollProgress = ref(0)
    const galleryTop = ref(null)
    // r=20 inside the button's 44x44 viewBox; the ring is drawn by shrinking
    // a dash offset from a full circumference down to zero.
    const RING_CIRCUMFERENCE = 2 * Math.PI * 20
    const ringOffset = computed(() => RING_CIRCUMFERENCE * (1 - scrollProgress.value / 100))

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

    // --- Map filter -------------------------------------------------------------------
    // Same shape as the logged-in gallery: the map is a view, offered from the tag dropdown,
    // held apart from `selectedTag` so it can never leak into recordings or analytics events.
    const MAP_FILTER_VALUE = '__map__'
    const mapMode = ref(false)
    const mapsEnabled = ref(false)
    const { ensureLoaded: ensureCapabilities } = useCapabilities()

    ensureCapabilities()
      .then(caps => { mapsEnabled.value = Boolean(caps.maps?.enabled) })
      .catch(() => { mapsEnabled.value = false })

    const hasLocatedFiles = computed(() =>
      allFilesUnfiltered.value.some(
        f => typeof f.gpsLatitude === 'number' && typeof f.gpsLongitude === 'number'
      )
    )

    const mapFilterAvailable = computed(() => mapsEnabled.value && hasLocatedFiles.value)

    const filterSelection = computed({
      get() {
        return mapMode.value ? MAP_FILTER_VALUE : selectedTag.value
      },
      set(value) {
        if (value === MAP_FILTER_VALUE) {
          mapMode.value = true
          // One dropdown, one active filter — see the same setter in GalleryView.
          selectedTag.value = ''
          return
        }
        mapMode.value = false
        selectedTag.value = value
      }
    })

    watch(mapFilterAvailable, available => {
      if (!available) mapMode.value = false
    })

    // --- By day & region --------------------------------------------------------------------
    // The same second reading of the album the owner gets: day sections, each cut into places at
    // most 2 km across (see utils/dayRegionGrouping.ts). Off during playback, where the recorded
    // slideshow drives the order and a re-shelved grid behind the lightbox would fight it.
    // Off on every visit, never remembered — same as the logged-in gallery.
    const dayRegionGrouping = ref(false)

    // Only once a tag is chosen: this groups the filtered set, it is not a way to open the whole
    // album past the filter prompt. Matches the logged-in gallery.
    const dayRegionAvailable = computed(
      () => Boolean(selectedTag.value) && !mapMode.value && files.value.length > 0
    )

    const dayRegionActive = computed(() =>
      dayRegionGrouping.value && dayRegionAvailable.value && !isPlaying.value
    )

    const dayRegionGroups = computed(() =>
      dayRegionActive.value
        ? groupByDayAndRegion(files.value, DEFAULT_REGION_RADIUS_METERS)
        : []
    )

    // Place names for the region headings; coordinates stand in until one arrives, and stay
    // for good when the server has no Apple Maps key.
    const { regionLabel } = useRegionNames()

    const presentationSections = computed(() =>
      buildSections(files.value, selectedTag.value)
    )

    const lightboxGroupContext = computed(() =>
      groupContextFor(presentationSections.value, selectedFile.value?.id)
    )

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

    // Scroll fires far more often than the browser can paint, so a burst of
    // events collapses into one measurement per animation frame.
    let scrollTicking = false

    function measureScroll() {
      scrollTicking = false
      const y = window.scrollY
      const scrollable = document.documentElement.scrollHeight - window.innerHeight
      showBackToTop.value = y > 400
      scrollProgress.value = scrollable > 0
        ? Math.min(100, Math.max(0, Math.round((y / scrollable) * 100)))
        : 0
    }

    function handleScroll() {
      if (scrollTicking) return
      scrollTicking = true
      requestAnimationFrame(measureScroll)
    }

    function scrollToTop() {
      // Honour the OS "reduce motion" setting: a long smooth scroll can trigger
      // motion sickness, so those users get an instant jump instead.
      const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' })
      // Move focus as well as the viewport, otherwise the next Tab press
      // continues from the bottom of the page the user just left.
      galleryTop.value?.focus({ preventScroll: true })
    }

    onUnmounted(() => {
      window.removeEventListener('scroll', handleScroll)
      window.removeEventListener('resize', handleScroll)
    })

    onMounted(async () => {
      window.addEventListener('scroll', handleScroll, { passive: true })
      // Page height changes as images load and when the device rotates.
      window.addEventListener('resize', handleScroll, { passive: true })
      measureScroll()
      await loadAlbumInfo()
      await loadAlbumFiles()
      await loadPublicGroups(props.shareToken)

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

        // 404 is what an unpublished album, a deleted album and a made-up token all return —
        // the server keeps them indistinguishable on purpose, and so does this message.
        if (response.status === 404) {
          albumUnavailable.value = true
          return
        }

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
          // The server already strips `hidden` assets out of this endpoint (D70); this is the
          // second lock on the same door. A tag name is one string compare per file, and the cost
          // of the server-side filter ever regressing is somebody's private photos on a public
          // page — so the client does not take the response's word for it.
          allFilesUnfiltered.value = (data.files || []).filter(
            file => !(file.tags || []).includes(HIDDEN_TAG)
          )
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

    return {
      album,
      albumUnavailable,
      albumMapViewValue,
      files,
      presentationSections,
      lightboxGroupContext,
      loadingFiles,
      selectedTag,
      allFilesUnfiltered,
      mapMode,
      mapFilterAvailable,
      dayRegionGrouping,
      dayRegionAvailable,
      dayRegionActive,
      dayRegionGroups,
      regionLabel,
      formatDayLabel,
      formatDistance,
      filterSelection,
      MAP_FILTER_VALUE,
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
      showBackToTop,
      scrollToTop,
      scrollProgress,
      ringOffset,
      RING_CIRCUMFERENCE,
      galleryTop
    }
  }
}
</script>
