<template>
  <div
    ref="rootElement"
    class="photo-map"
    :style="rootStyle"
  >
    <div
      v-if="error"
      class="map-message map-message--error"
    >
      <p class="map-message-title">
        The map could not be loaded
      </p>
      <p class="map-message-hint">
        {{ error }}
      </p>
    </div>

    <div
      v-else-if="locatedFiles.length === 0"
      class="map-message"
    >
      <p class="map-message-title">
        No photos with a location
      </p>
      <p class="map-message-hint">
        Only photos whose original still carries GPS data appear here. Photos uploaded before this
        feature existed need the one-off backfill (POST /api/admin/extract-gps).
      </p>
    </div>

    <template v-else>
      <div
        ref="mapElement"
        class="map-canvas"
      />

      <div
        v-if="loading"
        class="map-loading"
      >
        Loading map…
      </div>

      <!-- Setting the album's default view: drag and zoom the map to the framing you want, then
           press save. No coordinate entry, because the map itself is the better input. -->
      <div
        v-if="canEditView && !loading && !error"
        class="map-view-controls"
      >
        <button
          class="map-view-btn"
          title="Open the map at exactly this position and zoom for everyone viewing this album"
          @click="saveCurrentView"
        >
          📍 Save this view
        </button>
        <button
          v-if="savedView"
          class="map-view-btn map-view-btn--ghost"
          title="Go back to fitting every pin on screen"
          @click="$emit('clear-view')"
        >
          Reset
        </button>
      </div>

      <div
        v-if="selectedFiles.length > 0"
        class="map-selection"
      >
        <div class="map-selection-header">
          <strong>{{ selectedFiles.length }} {{ selectedFiles.length === 1 ? 'photo' : 'photos' }} here</strong>
          <button
            class="map-selection-close"
            title="Close"
            @click="selectedIds = []"
          >
            ✕
          </button>
        </div>
        <div class="map-selection-strip">
          <button
            v-for="file in selectedFiles"
            :key="file.id"
            class="map-selection-thumb"
            :title="file.originalName || file.filename"
            @click="$emit('open', file)"
          >
            <img
              :src="getImageUrl(file, 'thumb')"
              :alt="file.originalName || file.filename"
              loading="lazy"
            >
          </button>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { AlbumFile, MapView } from '@/types'
import { useApi } from '@/composables/useApi'
import {
  ensureMapKit,
  type MapKit,
  type MapKitAnnotation,
  type MapKitMap
} from '@/composables/useMapKit'

interface Props {
  files: AlbumFile[]
  /** The album's saved viewport, or null to frame every pin. */
  savedView?: MapView | null
  /** Whether to offer the save/reset controls — the album owner, not a share-link visitor. */
  canEditView?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  savedView: null,
  canEditView: false
})

const emit = defineEmits<{
  open: [file: AlbumFile]
  'save-view': [view: MapView]
  'clear-view': []
}>()

/**
 * Hands the map's current viewport to the parent to persist.
 *
 * <p>Reads it off the live map rather than tracking pans ourselves: MapKit already maintains
 * `region` through drags, pinches, double-taps and its own showItems animation, and any shadow
 * copy we kept would only be a chance to disagree with what the owner is looking at.
 */
function saveCurrentView(): void {
  if (!map) return
  const { center, span } = map.region
  emit('save-view', {
    centerLat: center.latitude,
    centerLng: center.longitude,
    spanLat: span.latitudeDelta,
    spanLng: span.longitudeDelta
  })
}

const { getImageUrl } = useApi()

const rootElement = ref<HTMLElement | null>(null)
const mapElement = ref<HTMLElement | null>(null)
const measuredHeight = ref(0)
const loading = ref(true)
const error = ref<string | null>(null)
const selectedIds = ref<number[]>([])

// Breathing room between the map and whatever follows it on the page.
const BOTTOM_GAP_PX = 16
// Below this a map is more frustrating than useful, so we let the page scroll instead.
const MIN_HEIGHT_PX = 320

const rootStyle = computed(() =>
  measuredHeight.value > 0 ? { height: `${measuredHeight.value}px` } : {}
)

/**
 * Adds up the real content sitting below this element: every following sibling on the way up to
 * `<body>`, plus each ancestor's bottom padding and border.
 *
 * <p>Measured this way and not as `scrollHeight - elementBottom`, which looks equivalent and is
 * not: the app sets `#app { min-height: 100vh }`, so a short page still reports a full screen of
 * height. That version counted the very whitespace we are trying to reclaim as content below the
 * map, and quietly made the map *smaller*.
 *
 * <p>Elements taken out of flow (the toast host, dialogs, the lightbox overlay) are skipped —
 * they float above the page and occupy no vertical space in it.
 */
function trailingSpace(el: HTMLElement): number {
  let total = 0
  let node: HTMLElement | null = el

  while (node && node !== document.body && node.parentElement) {
    for (
      let sibling = node.nextElementSibling;
      sibling instanceof HTMLElement;
      sibling = sibling.nextElementSibling
    ) {
      const style = window.getComputedStyle(sibling)
      if (style.display === 'none' || style.position === 'fixed' || style.position === 'absolute') {
        continue
      }
      total +=
        sibling.getBoundingClientRect().height +
        parseFloat(style.marginTop) +
        parseFloat(style.marginBottom)
    }

    const parentStyle = window.getComputedStyle(node.parentElement)
    total += parseFloat(parentStyle.paddingBottom) + parseFloat(parentStyle.borderBottomWidth)
    node = node.parentElement
  }

  return total
}

/**
 * Sizes the map to the space actually left on screen, rather than a guessed `70vh`.
 *
 * <p>Uses the element's document-absolute top so the answer does not change with scroll
 * position, and pairs it with {@link trailingSpace} so the map stops just above the app footer
 * instead of pushing it off screen. The logged-in gallery and a public share link carry
 * different furniture down there, which is why none of this is hardcoded.
 */
function measureHeight(): void {
  const el = rootElement.value
  if (!el) return
  const absoluteTop = el.getBoundingClientRect().top + window.scrollY
  const available =
    window.innerHeight - absoluteTop - trailingSpace(el) - BOTTOM_GAP_PX
  measuredHeight.value = Math.max(MIN_HEIGHT_PX, Math.round(available))
}

let map: MapKitMap | null = null
let mapkitRef: MapKit | null = null
// The pins currently on the map, kept so "Reset" can re-fit to them without a full rebuild.
let currentAnnotations: MapKitAnnotation[] = []
// Guards against two builds overlapping: `buildMap` awaits a network round-trip, and a second
// change (album reload, filter flip) during that await would otherwise leave an orphaned map
// instance attached to the element and never destroyed.
let buildToken = 0

const locatedFiles = computed(() =>
  props.files.filter(
    (file) =>
      typeof file.gpsLatitude === 'number' && typeof file.gpsLongitude === 'number'
  )
)

/**
 * Groups files into pins. The key rounds to four decimal places — about 11 m — so a burst shot
 * from one spot becomes one pin instead of a smear of overlapping ones, while two ends of a
 * street stay apart. Anything closer together than that on screen is handled by MapKit's own
 * clustering, which merges pins by distance in pixels rather than in degrees.
 */
const places = computed(() => {
  const byKey = new Map<string, AlbumFile[]>()
  for (const file of locatedFiles.value) {
    const key = `${file.gpsLatitude!.toFixed(4)},${file.gpsLongitude!.toFixed(4)}`
    const bucket = byKey.get(key)
    if (bucket) {
      bucket.push(file)
    } else {
      byKey.set(key, [file])
    }
  }
  return [...byKey.values()]
})

// Selection is held as ids, not file objects, so a reload of the album (new objects, same ids)
// keeps the open pin's strip pointing at live data instead of stale copies.
const selectedFiles = computed(() =>
  selectedIds.value
    .map((id) => props.files.find((file) => file.id === id))
    .filter((file): file is AlbumFile => Boolean(file))
)

async function buildMap(): Promise<void> {
  if (!mapElement.value || places.value.length === 0) return
  // Size the container before MapKit reads it, so the first frame is already right.
  measureHeight()
  const token = ++buildToken
  loading.value = true
  error.value = null

  try {
    const mapkit = await ensureMapKit()
    // Bail if the element went away or a newer build started while the token round-trip was in
    // flight (user switched filter, album reloaded).
    if (!mapElement.value || token !== buildToken) return

    destroyMap()
    map = new mapkit.Map(mapElement.value, {
      // MapKit's FeatureVisibility values are lowercase strings; anything else is rejected.
      showsCompass: 'adaptive',
      showsScale: 'adaptive'
    })

    const annotations = places.value.map((filesAtPlace) => {
      const first = filesAtPlace[0]
      const coordinate = new mapkit.Coordinate(first.gpsLatitude!, first.gpsLongitude!)
      return new mapkit.MarkerAnnotation(coordinate, {
        title: filesAtPlace.length === 1 ? '1 photo' : `${filesAtPlace.length} photos`,
        // Merges pins that overlap at the current zoom into one numbered cluster. Every pin
        // shares the identifier because they are all the same kind of thing.
        clusteringIdentifier: 'photos',
        // A count only earns the glyph when there is something to count; a lone pin reading "1"
        // is noise. Three digits is where the marker starts clipping.
        glyphText:
          filesAtPlace.length > 1
            ? (filesAtPlace.length > 99 ? '99+' : String(filesAtPlace.length))
            : '📷',
        data: { fileIds: filesAtPlace.map((file) => file.id) }
      })
    })

    map.addEventListener('select', (event) => {
      const annotation = event.annotation
      // A cluster carries its members; a plain pin is its own single member.
      const members = annotation.memberAnnotations ?? [annotation]
      selectedIds.value = members.flatMap((member) => member.data?.fileIds ?? [])
    })
    map.addEventListener('deselect', () => {
      selectedIds.value = []
    })

    map.addAnnotations(annotations)
    mapkitRef = mapkit
    currentAnnotations = annotations
    applyInitialRegion(mapkit, annotations)
  } catch (err) {
    if (token !== buildToken) return
    error.value = err instanceof Error ? err.message : 'Unknown error'
    console.error('Map initialisation failed:', err)
  } finally {
    if (token === buildToken) loading.value = false
  }
}

/**
 * Positions a freshly built map: the album's saved view if it has one, otherwise a frame around
 * every pin.
 *
 * <p>Auto-fit is the better default — an album can span one park or three continents and both
 * should open readable — but it is only ever a guess at what the album is *about*. A trip whose
 * photos are all in Toronto except three from the airport layover fits to include the layover and
 * opens showing mostly water. The saved view is the owner overriding that guess, so it wins
 * outright rather than being merged with the pin bounds.
 */
function applyInitialRegion(mapkit: MapKit, annotations: MapKitAnnotation[]): void {
  if (!map) return

  const view = props.savedView
  if (view) {
    map.region = new mapkit.CoordinateRegion(
      new mapkit.Coordinate(view.centerLat, view.centerLng),
      new mapkit.CoordinateSpan(view.spanLat, view.spanLng)
    )
    return
  }

  map.showItems(annotations, {
    padding: new mapkit.Padding({ top: 48, right: 48, bottom: 48, left: 48 })
  })
}

function destroyMap(): void {
  if (map) {
    map.destroy()
    map = null
  }
  mapkitRef = null
  currentAnnotations = []
}

watch(
  [mapElement, places],
  () => {
    selectedIds.value = []
    void buildMap()
  },
  { immediate: true }
)

/**
 * Re-frames when the saved view is added or removed under us — the owner pressing save or reset.
 *
 * <p>Deliberately not a rebuild: the pins have not changed, and tearing the map down would flash
 * the tiles and close whatever pin the owner had open. After a save the region we re-apply is the
 * one already on screen, so that case is a visual no-op; after a reset it re-fits to the pins.
 */
watch(
  () => props.savedView,
  () => {
    if (!map || !mapkitRef) return
    applyInitialRegion(mapkitRef, currentAnnotations)
  }
)

// iOS reports the new viewport a beat after the rotation event fires, so re-measure late.
function measureAfterRotation(): void {
  window.setTimeout(measureHeight, 200)
}

onMounted(() => {
  // After paint: the element has no position to measure until the view has laid out. The second
  // pass on the next frame catches furniture that lands late — web fonts reflowing the footer,
  // the version line arriving from /api/version.
  void nextTick(() => {
    measureHeight()
    window.requestAnimationFrame(measureHeight)
  })
  window.addEventListener('resize', measureHeight)
  window.addEventListener('orientationchange', measureAfterRotation)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', measureHeight)
  window.removeEventListener('orientationchange', measureAfterRotation)
  destroyMap()
})
</script>

<style scoped>
.photo-map {
  position: relative;
  width: 100%;
  /* Fallback for the frame before measureHeight() runs; the inline style then wins. */
  height: 70vh;
  min-height: 320px;
  border-radius: 12px;
  overflow: hidden;
  background: rgba(127, 127, 127, 0.12);
}

.map-canvas {
  width: 100%;
  height: 100%;
}

.map-loading {
  position: absolute;
  top: 12px;
  left: 50%;
  transform: translateX(-50%);
  padding: 6px 14px;
  border-radius: 999px;
  background: rgba(0, 0, 0, 0.65);
  color: #fff;
  font-size: 0.85rem;
}

/* Top-left, clear of MapKit's own furniture: the loading pill is centred, the map-type toggle
   sits top-right, and the zoom/compass controls bottom-right. */
.map-view-controls {
  position: absolute;
  top: 12px;
  left: 12px;
  display: flex;
  gap: 6px;
}

.map-view-btn {
  padding: 7px 12px;
  border: none;
  border-radius: 999px;
  background: rgba(20, 20, 20, 0.82);
  color: #fff;
  font-size: 0.8125rem;
  font-weight: 600;
  cursor: pointer;
  backdrop-filter: blur(6px);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
}

.map-view-btn:hover {
  background: rgba(20, 20, 20, 0.95);
}

.map-view-btn--ghost {
  background: rgba(255, 255, 255, 0.9);
  color: #222;
  font-weight: 500;
}

.map-view-btn--ghost:hover {
  background: #fff;
}

.map-message {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  height: 100%;
  padding: 24px;
  text-align: center;
}

.map-message-title {
  font-weight: 600;
  margin: 0;
}

.map-message-hint {
  margin: 0;
  max-width: 42ch;
  opacity: 0.7;
  font-size: 0.9rem;
}

.map-message--error .map-message-title {
  color: #c0392b;
}

.map-selection {
  position: absolute;
  left: 12px;
  right: 12px;
  bottom: 12px;
  padding: 10px 12px;
  border-radius: 12px;
  background: rgba(20, 20, 20, 0.88);
  color: #fff;
  backdrop-filter: blur(6px);
}

.map-selection-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
  font-size: 0.9rem;
}

.map-selection-close {
  background: none;
  border: none;
  color: inherit;
  cursor: pointer;
  font-size: 1rem;
  line-height: 1;
  padding: 2px 6px;
}

.map-selection-strip {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 4px;
}

.map-selection-thumb {
  flex: 0 0 auto;
  padding: 0;
  border: 2px solid transparent;
  border-radius: 8px;
  background: none;
  cursor: pointer;
  line-height: 0;
}

.map-selection-thumb:hover {
  border-color: #fff;
}

.map-selection-thumb img {
  width: 72px;
  height: 72px;
  object-fit: cover;
  border-radius: 6px;
}
</style>
