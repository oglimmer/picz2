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
        v-if="dayRegionAvailable"
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
          v-if="hasRecordingFor(selectedTag, 'language1')"
          class="play-btn"
          :title="`Play ${language1Name} recorded slideshow`"
          @click="startPlayback(selectedTag, 'language1')"
        >
          ▶️ Play {{ language1Name }}
        </button>
        <button
          v-if="hasRecordingFor(selectedTag, 'language2')"
          class="play-btn"
          :title="`Play ${language2Name} recorded slideshow`"
          @click="startPlayback(selectedTag, 'language2')"
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

    <!-- By day & region: only reachable with a tag selected, so it never stands in for the
         "pick a tag" prompt below. -->
    <DayRegionSections
      v-else-if="dayRegionActive"
      :groups="dayRegionGroups"
      grid-class="presentation-gallery"
    >
      <template #default="{ file }">
        <PublicPhotoTile
          :file="file"
          @open="openImage"
        />
      </template>
    </DayRegionSections>

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
    <PresentationSectionList
      v-else
      :sections="presentationSections"
    >
      <template #default="{ file }">
        <PublicPhotoTile
          :file="file"
          @open="openImage"
        />
      </template>
    </PresentationSectionList>

    <!-- Lightbox -->
    <Lightbox
      :file="selectedFile"
      :group-context="lightboxGroupContext"
      :is-playing="isPlaying"
      :is-paused="isPaused"
      @close="closeLightbox"
      @next="navigateNext"
      @previous="navigatePrevious"
      @pause-resume="pauseResume"
      @stop-playback="stopPlayback"
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
      @close="showSubscriptionDialog = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted, nextTick, useTemplateRef } from 'vue'
import { ApiError, useApi } from '@/composables/useApi'
import { useSettings } from '@/composables/useSettings'
import { useAnalytics } from '@/composables/useAnalytics'
import { usePresentationGroups } from '@/composables/usePresentationGroups'
import { useLightboxNavigation } from '@/composables/useLightboxNavigation'
import { usePlaybackControls } from '@/composables/usePlaybackControls'
import { useMapViewMode } from '@/composables/useMapViewMode'
import { useDayRegionView } from '@/composables/useDayRegionView'
import { countTags } from '@/utils/tags'
import { readCookie } from '@/utils/cookies'
import { albumMapView, type Album, type AlbumFile } from '@/types'
import Lightbox from '@/components/Lightbox.vue'
import CookieConsent from '@/components/CookieConsent.vue'
import SubscriptionDialog from '@/components/SubscriptionDialog.vue'
import PhotoMap from '@/components/PhotoMap.vue'
import DayRegionSections from '@/components/DayRegionSections.vue'
import PresentationSectionList from '@/components/PresentationSectionList.vue'
import PublicPhotoTile from '@/components/PublicPhotoTile.vue'

interface Props {
  shareToken: string
  imageToken?: string | null
  openLightbox?: boolean
}

const props = withDefaults(defineProps<Props>(), { imageToken: null, openLightbox: false })

const { apiUrl, requestPublicJson, shareToken } = useApi()

// Set the share token for API requests
shareToken.value = props.shareToken

const album = ref<Album | null>(null)
// Set when the public album endpoint answers 404: not shared, removed, or never existed.
const albumUnavailable = ref(false)
// The owner's saved framing for the map filter, if they set one. Read-only here: a share-link
// visitor can pan and zoom all they like, but nothing they do is persisted.
const albumMapViewValue = computed(() => albumMapView(album.value))
// Never offered as a filter and never counted: an asset carrying it is dropped on arrival.
const HIDDEN_TAG = 'hidden'
const allFilesUnfiltered = ref<AlbumFile[]>([])
const loadingFiles = ref(false)
const selectedTag = ref('')
const isInitialLoad = ref(true)

const { language1Name, language2Name, loadLanguageSettings } = useSettings()
const { loadPublicGroups, buildSections, groupContextFor } = usePresentationGroups()
const { consentGiven, logPageView, logFilterChange, logAudioPlay } = useAnalytics()

// Track if consent choice has been made (to avoid duplicate page view logs)
const consentChoiceMade = ref(false)

const showBackToTop = ref(false)
const scrollProgress = ref(0)
const galleryTop = ref<HTMLElement | null>(null)
// r=20 inside the button's 44x44 viewBox; the ring is drawn by shrinking
// a dash offset from a full circumference down to zero.
const RING_CIRCUMFERENCE = 2 * Math.PI * 20
const ringOffset = computed(() => RING_CIRCUMFERENCE * (1 - scrollProgress.value / 100))

const showSubscriptionDialog = ref(false)

// Filtered files based on selected tag
const files = computed(() =>
  selectedTag.value
    ? allFilesUnfiltered.value.filter((file) => file.tags?.includes(selectedTag.value))
    : allFilesUnfiltered.value
)

const { selectedFile, open: openImage, next: navigateNext, previous: navigatePrevious } =
  useLightboxNavigation(files)

const audioPlayer = useTemplateRef<HTMLAudioElement>('audioPlayer')
const {
  playback,
  isPaused,
  controlsVisible,
  startPlayback,
  pauseResume,
  stop: stopPlayback
} = usePlaybackControls(files, selectedFile, audioPlayer, (recording, tag) =>
  logAudioPlay(props.shareToken, recording.id, tag || undefined)
)
const { isPlaying, recordings, loadRecordings, hasRecordings, hasRecordingFor } = playback

// --- Map filter -------------------------------------------------------------------
// The map is a view, offered from the tag dropdown, held apart from `selectedTag` so it can
// never leak into recordings or analytics events.
const MAP_FILTER_VALUE = '__map__'
const { mapMode, mapFilterAvailable } = useMapViewMode(allFilesUnfiltered)

const filterSelection = computed({
  get: () => (mapMode.value ? MAP_FILTER_VALUE : selectedTag.value),
  set(value: string) {
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

// --- By day & region ----------------------------------------------------------------------
// Off during playback, where the recorded slideshow drives the order and a re-shelved grid
// behind the lightbox would fight it.
const { dayRegionGrouping, dayRegionAvailable, dayRegionActive, dayRegionGroups } =
  useDayRegionView(
    files,
    () => Boolean(selectedTag.value) && !mapMode.value && files.value.length > 0 && !isPlaying.value
  )

const presentationSections = computed(() => buildSections(files.value, selectedTag.value))
const lightboxGroupContext = computed(() =>
  groupContextFor(presentationSections.value, selectedFile.value?.id)
)
const tagsUsedInAlbum = computed(() => countTags(allFilesUnfiltered.value))

// Send analytics for user-initiated tag changes only (not the initial load or a clear)
watch(selectedTag, async (newTag) => {
  if (isInitialLoad.value || !newTag) return
  await logFilterChange(props.shareToken, newTag)
})

// Auto-select tag when there's only one tag
watch(tagsUsedInAlbum, (tags) => {
  if (tags.length === 1) selectedTag.value = tags[0].name
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
  await loadLanguageSettings()

  if (album.value) {
    await loadRecordings(album.value.id)
  }

  // If imageToken is provided, open that specific image
  if (props.openLightbox && props.imageToken) {
    const file = files.value.find((f) => f.publicToken === props.imageToken)
    if (file) openImage(file)
  }

  // After initial load and auto-selection, mark as ready for analytics tracking
  await nextTick()
  isInitialLoad.value = false

  // A returning visitor has already answered the banner: log the page view now. A new one is
  // logged from handleConsent() once they choose.
  if (readCookie('cookie_consent') !== null) {
    consentChoiceMade.value = true
    await logPageView(props.shareToken, selectedTag.value || undefined)
  }
})

async function loadAlbumInfo() {
  try {
    const data = await requestPublicJson<{ album?: Album }>(
      `${apiUrl}/api/albums/public/${props.shareToken}`
    )
    if (data.album) album.value = data.album
  } catch (err) {
    // 404 is what an unpublished album, a deleted album and a made-up token all return —
    // the server keeps them indistinguishable on purpose, and so does this message.
    if (err instanceof ApiError && err.status === 404) albumUnavailable.value = true
  }
}

async function loadAlbumFiles() {
  loadingFiles.value = true
  try {
    const data = await requestPublicJson<{ files?: AlbumFile[] }>(
      `${apiUrl}/api/albums/public/${props.shareToken}/files`
    )
    // The server already strips `hidden` assets out of this endpoint (D70); this is the
    // second lock on the same door. A tag name is one string compare per file, and the cost
    // of the server-side filter ever regressing is somebody's private photos on a public
    // page — so the client does not take the response's word for it.
    allFilesUnfiltered.value = (data.files || []).filter(
      (file) => !(file.tags || []).includes(HIDDEN_TAG)
    )
  } catch {
    // The empty state says "No photos"; the album header already explains an unavailable album.
  } finally {
    loadingFiles.value = false
  }
}

function closeLightbox() {
  // Stop audio playback when closing the lightbox
  if (isPlaying.value) {
    playback.stopPlayback()
    controlsVisible.value = true
  }
  selectedFile.value = null
}

async function handleConsent(accepted: boolean) {
  consentGiven(accepted)
  // After the choice, log the page view: with the visitor_id cookie if accepted, without if not.
  if (!consentChoiceMade.value) {
    consentChoiceMade.value = true
    await logPageView(props.shareToken, selectedTag.value || undefined)
  }
}
</script>
