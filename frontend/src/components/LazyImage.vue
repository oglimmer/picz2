<template>
  <div
    ref="root"
    class="lazy-image"
    :class="{ 'is-loaded': loaded, 'is-failed': failed }"
  >
    <img
      v-if="committedSrc"
      ref="imgEl"
      :src="committedSrc"
      :alt="alt"
      loading="lazy"
      decoding="async"
      @load="onLoad"
      @error="onError"
    >
    <span
      v-if="failed"
      class="lazy-image__failed"
      title="This image could not be loaded"
    >⚠</span>
    <span
      v-else-if="!loaded"
      class="lazy-image__skeleton"
      aria-hidden="true"
    />
  </div>
</template>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

/**
 * A thumbnail that decides *when* to hit the network, not just whether to.
 *
 * `loading="lazy"` alone is not enough for a long gallery. It starts a fetch as soon as an image
 * comes near the viewport and the browser never cancels that fetch when the image scrolls back
 * out — so flicking through a few hundred photos enqueues a few hundred GETs, all at the same
 * priority, in DOM order. Whatever is on screen when you stop ends up at the back of that queue
 * and sits in "Queued"/"Stalled" until everything you scrolled past has been served.
 *
 * So we hold the `src` back until one of two things is true:
 *   - the user stopped scrolling and this tile is still in the band, or
 *   - the tile has lingered in the band for DWELL_MS, which only happens on a slow scroll.
 *
 * Fast scrolling therefore requests nothing; the moment you stop, the visible rows load against
 * an empty queue. Slow scrolling still pre-loads ahead of the viewport as before.
 */

interface Props {
  src: string
  alt?: string
}

const props = withDefaults(defineProps<Props>(), { alt: '' })

/** How far outside the viewport a tile starts counting as "worth loading". */
const ROOT_MARGIN = '400px 0px'
/** Quiet period after the last scroll event before we call the scroll finished. */
const SCROLL_IDLE_MS = 120
/** Continuous time in the band that earns a load even while the user is still scrolling. */
const DWELL_MS = 350

// --- Module-level scroll state, shared by every tile ------------------------------------------
// One observer and one scroll listener for the whole gallery; a few hundred of each would cost
// more than the problem being solved.

type Tile = { enter: () => void; leave: () => void }

const tiles = new WeakMap<Element, Tile>()
let observer: IntersectionObserver | null = null

function sharedObserver(): IntersectionObserver | null {
  if (observer) return observer
  if (typeof IntersectionObserver === 'undefined') return null
  observer = new IntersectionObserver(
    entries => {
      for (const entry of entries) {
        const tile = tiles.get(entry.target)
        if (!tile) continue
        if (entry.isIntersecting) tile.enter()
        else tile.leave()
      }
    },
    { rootMargin: ROOT_MARGIN }
  )
  return observer
}

let scrolling = false
let idleTimer: ReturnType<typeof setTimeout> | undefined
const idleWaiters = new Set<() => void>()
let scrollHooked = false

function onScroll() {
  scrolling = true
  clearTimeout(idleTimer)
  idleTimer = setTimeout(() => {
    scrolling = false
    // Copy first: a waiter commits and unregisters itself, which mutates the set.
    const waiting = [...idleWaiters]
    idleWaiters.clear()
    for (const waiter of waiting) waiter()
  }, SCROLL_IDLE_MS)
}

function hookScroll() {
  if (scrollHooked || typeof window === 'undefined') return
  // Capture phase so scrolling inside a nested container counts too, not just the document.
  window.addEventListener('scroll', onScroll, { passive: true, capture: true })
  scrollHooked = true
}

// --- Instance ---------------------------------------------------------------------------------

const root = ref<HTMLElement | null>(null)
const imgEl = ref<HTMLImageElement | null>(null)
const committedSrc = ref('')
const loaded = ref(false)
const failed = ref(false)
let dwellTimer: ReturnType<typeof setTimeout> | undefined

function commit() {
  cancelPending()
  if (!props.src || committedSrc.value === props.src) return
  committedSrc.value = props.src
  // Nothing left to watch for — the browser owns this image from here on.
  if (root.value) {
    observer?.unobserve(root.value)
    tiles.delete(root.value)
  }
}

function cancelPending() {
  clearTimeout(dwellTimer)
  dwellTimer = undefined
  idleWaiters.delete(commit)
}

function enter() {
  if (committedSrc.value) return
  if (!scrolling) {
    commit()
    return
  }
  idleWaiters.add(commit)
  if (dwellTimer === undefined) dwellTimer = setTimeout(commit, DWELL_MS)
}

function leave() {
  if (committedSrc.value) return
  cancelPending()
}

function onLoad() {
  loaded.value = true
  failed.value = false
}

function onError() {
  failed.value = true
}

onMounted(() => {
  hookScroll()
  const io = sharedObserver()
  if (!io || !root.value) {
    // No IntersectionObserver (or no element): fall back to the browser's own lazy loading.
    commit()
    return
  }
  tiles.set(root.value, { enter, leave })
  io.observe(root.value)
})

onBeforeUnmount(() => {
  cancelPending()
  if (root.value) {
    observer?.unobserve(root.value)
    tiles.delete(root.value)
  }
})

// A rotate swaps the asset's publicToken, so the URL changes under a tile that already loaded.
watch(
  () => props.src,
  next => {
    if (!committedSrc.value || committedSrc.value === next) return
    committedSrc.value = next
    loaded.value = false
    failed.value = false
  }
)

// If the image is already in the browser cache it can finish before the load listener runs.
watch(committedSrc, async () => {
  await nextTick()
  const el = imgEl.value
  if (el?.complete && el.naturalWidth > 0) loaded.value = true
})
</script>
