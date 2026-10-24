<template>
  <div class="analytics-page">
    <header class="picz-header">
      <router-link
        to="/albums"
        class="brand-wordmark"
      >
        Picz
      </router-link>
      <div class="crumb">
        <router-link
          class="crumb-link"
          :to="{ name: 'Album', params: { albumId: String(albumId) } }"
        >
          <svg
            width="11"
            height="11"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M19 12H5M11 18l-6-6 6-6" />
          </svg>
          <span class="crumb-name">{{ album?.name || 'Album' }}</span>
        </router-link>
      </div>
      <AccountMenu />
    </header>

    <div class="analytics-head">
      <h1 class="page-title">
        Analytics
      </h1>
      <div class="analytics-status">
        <span
          class="receiving-dot"
          :class="counting ? 'receiving-dot--live' : 'receiving-dot--paused'"
        />
        <span class="receiving-label">{{ counting ? 'Counting visits' : 'Counting paused' }}</span>
      </div>
    </div>

    <div class="shelf">
      <p class="shelf-count">
        <strong>{{ (stats?.totalEvents ?? 0).toLocaleString() }}</strong>&nbsp;events recorded
      </p>
      <span class="shelf-rule" />
      <div class="shelf-controls">
        <button
          class="action-link"
          :disabled="loading"
          @click="load"
        >
          {{ loading ? 'Refreshing…' : 'Refresh' }}
        </button>
        <button
          class="btn"
          :disabled="!stats || saving"
          @click="togglePaused"
        >
          {{ counting ? 'Pause counting' : 'Resume counting' }}
        </button>
      </div>
    </div>

    <div
      v-if="loading && !stats"
      class="status-loading"
    >
      Loading analytics…
    </div>

    <div
      v-else-if="error"
      class="status-error"
    >
      {{ error }}
    </div>

    <template v-else-if="stats">
      <p
        v-if="!counting"
        class="analytics-paused-notice"
      >
        Counting is paused — visits to the shared album are not being recorded. The figures below
        are what was collected before you paused.
      </p>

      <div class="analytics-body">
        <!-- Hero: the one number this page leads with. -->
        <div class="figure-hero">
          <p class="figure-hero-value">
            {{ stats.uniqueVisitors.toLocaleString() }}
          </p>
          <p class="figure-hero-label">
            Unique visitors
          </p>
        </div>

        <div class="figure-row">
          <div class="figure-tile">
            <p class="figure-value">
              {{ stats.pageViews.toLocaleString() }}
            </p>
            <p class="figure-label">
              Page views
            </p>
          </div>
          <div class="figure-tile">
            <p class="figure-value">
              {{ stats.filterChanges.toLocaleString() }}
            </p>
            <p class="figure-label">
              Filter changes
            </p>
          </div>
          <div class="figure-tile">
            <p class="figure-value">
              {{ stats.audioPlays.toLocaleString() }}
            </p>
            <p class="figure-label">
              Audio plays
            </p>
          </div>
        </div>

        <!--
          One measure across a handful of named tags: a ranked bar list, one hue for every bar
          (a darker-where-bigger ramp would encode length twice). The value beside each row is
          the table view, so the bars are pure reinforcement.
        -->
        <section
          v-if="rankedFilters.length > 0"
          class="bar-list-section"
        >
          <h2 class="section-title">
            Filters visitors chose
          </h2>
          <dl class="bar-list">
            <div
              v-for="row in rankedFilters"
              :key="row.tag"
              class="bar-row"
              :title="`${row.share}% of all filter changes`"
            >
              <dt class="bar-label">
                {{ row.tag }}
              </dt>
              <div class="bar-track">
                <div
                  class="bar-fill"
                  :style="{ width: row.width + '%' }"
                />
              </div>
              <dd class="bar-value">
                {{ row.count.toLocaleString() }}
              </dd>
            </div>
          </dl>
          <p
            v-if="hiddenFilterCount > 0"
            class="bar-list-note"
          >
            {{ hiddenFilterCount }} more {{ hiddenFilterCount === 1 ? 'tag' : 'tags' }} with fewer
            events {{ hiddenFilterCount === 1 ? 'is' : 'are' }} not shown.
          </p>
        </section>

        <!--
          Per-photo looks (D90). Two measures of one thing — how a visitor got to the photo — so
          each row is one stacked bar: opened from the grid, then walked to inside the lightbox.
          The numbers beside it are the table view; the hover title spells the row out.
        -->
        <section
          v-if="stats.imagesInAlbum > 0"
          class="bar-list-section"
        >
          <h2 class="section-title">
            Photos looked at full screen
          </h2>

          <div class="figure-row image-views-figures">
            <div class="figure-tile">
              <p class="figure-value">
                {{ stats.imagesViewed.toLocaleString() }}
                <span class="figure-value-of">of {{ stats.imagesInAlbum.toLocaleString() }}</span>
              </p>
              <p class="figure-label">
                Photos looked at
              </p>
            </div>
            <div class="figure-tile">
              <p class="figure-value">
                {{ stats.imageOpens.toLocaleString() }}
              </p>
              <p class="figure-label">
                Opened by a click
              </p>
            </div>
            <div class="figure-tile">
              <p class="figure-value">
                {{ stats.imageWalkIns.toLocaleString() }}
              </p>
              <p class="figure-label">
                Walked through
              </p>
            </div>
          </div>

          <p
            v-if="stats.imagesViewed === 0"
            class="bar-list-note"
          >
            Nobody has looked at a photo full screen yet.
          </p>

          <template v-else>
            <p class="image-views-summary">
              {{ coverageSentence }}
            </p>

            <div
              class="image-views-legend"
              aria-hidden="true"
            >
              <span class="image-views-key"><span class="image-views-swatch image-views-swatch--opens" />Opened by a click</span>
              <span class="image-views-key"><span class="image-views-swatch image-views-swatch--walks" />Walked through</span>
            </div>

            <ol class="image-views-list">
              <li
                v-for="(row, index) in visibleImageRows"
                :key="row.fileId"
                class="image-views-row"
                :title="row.tooltip"
              >
                <span class="image-views-rank">{{ index + 1 }}</span>
                <img
                  v-if="row.thumbUrl"
                  class="image-views-thumb"
                  :src="row.thumbUrl"
                  :alt="row.originalName"
                  loading="lazy"
                >
                <span
                  v-else
                  class="image-views-thumb"
                />
                <div class="image-views-main">
                  <span class="image-views-name">{{ row.originalName }}</span>
                  <div
                    class="image-views-bar"
                    :style="{ width: row.width + '%' }"
                  >
                    <span
                      v-if="row.opens > 0"
                      class="image-views-seg image-views-seg--opens"
                      :style="{ flexGrow: row.opens }"
                    />
                    <span
                      v-if="row.walkIns > 0"
                      class="image-views-seg image-views-seg--walks"
                      :style="{ flexGrow: row.walkIns }"
                    />
                  </div>
                </div>
                <span class="image-views-value">
                  <strong>{{ row.total.toLocaleString() }}</strong>
                  <span class="image-views-people">{{ row.viewers }} {{ row.viewers === 1 ? 'person' : 'people' }}</span>
                </span>
              </li>
            </ol>

            <button
              v-if="imageRows.length > IMAGE_ROWS"
              class="action-link image-views-more"
              @click="showAllImages = !showAllImages"
            >
              {{ showAllImages ? 'Show fewer' : `Show top ${imageRows.length}` }}
            </button>
          </template>
        </section>

        <section class="danger-strip">
          <div class="danger-strip-copy">
            <h2 class="section-title">
              Reset analytics
            </h2>
            <p class="danger-strip-hint">
              Deletes every recorded event for this album. Your photos and the album itself are
              untouched. This cannot be undone.
            </p>
          </div>
          <button
            class="btn-danger"
            :disabled="saving"
            @click="handleReset"
          >
            Reset analytics
          </button>
        </section>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useAlbums } from '../composables/useAlbums'
import { useApi } from '../composables/useApi'
import { useAnalytics, type AnalyticsStats } from '../composables/useAnalytics'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import AccountMenu from '../components/AccountMenu.vue'
import type { Album } from '@/types'

interface Props {
  albumId: string | number
}

const props = defineProps<Props>()

const { loadAlbumById } = useAlbums()
const { getAlbumStatistics, resetAlbumAnalytics, setAnalyticsPaused } = useAnalytics()
const { success, error: showError } = useNotifications()
const { confirm: confirmDialog } = useConfirm()
const { getImageUrl } = useApi()

const album = ref<Album | null>(null)
const stats = ref<AnalyticsStats | null>(null)
const loading = ref(false)
const saving = ref(false)
const error = ref<string | null>(null)

const numericId = computed(() => Number(props.albumId))
const counting = computed(() => Boolean(stats.value) && !stats.value?.analyticsPaused)

/** Top tags by event count, each scaled against the busiest one. */
const FILTER_ROWS = 8

const sortedFilters = computed(() =>
  Object.entries(stats.value?.filterTagCounts ?? {})
    .map(([tag, count]) => ({ tag, count: Number(count) }))
    .sort((a, b) => b.count - a.count)
)

const hiddenFilterCount = computed(() => Math.max(0, sortedFilters.value.length - FILTER_ROWS))

const rankedFilters = computed(() => {
  const rows = sortedFilters.value.slice(0, FILTER_ROWS)
  const max = rows[0]?.count || 1
  const total = sortedFilters.value.reduce((sum, r) => sum + r.count, 0) || 1
  return rows.map(r => ({
    ...r,
    width: Math.max(2, Math.round((r.count / max) * 100)),
    share: Math.round((r.count / total) * 100)
  }))
})

/** The most looked-at photos, scaled against the busiest one. */
const IMAGE_ROWS = 10
const showAllImages = ref(false)

const imageRows = computed(() => {
  const rows = stats.value?.topImages ?? []
  const max = rows.reduce((m, r) => Math.max(m, r.opens + r.walkIns), 0) || 1
  return rows.map(r => {
    const total = r.opens + r.walkIns
    return {
      ...r,
      total,
      width: Math.max(2, Math.round((total / max) * 100)),
      thumbUrl: getImageUrl(r, 'thumb'),
      tooltip:
        `${r.originalName}: opened ${r.opens.toLocaleString()} ${r.opens === 1 ? 'time' : 'times'}, ` +
        `walked through ${r.walkIns.toLocaleString()} ${r.walkIns === 1 ? 'time' : 'times'}, ` +
        `by ${r.viewers} ${r.viewers === 1 ? 'person' : 'people'}`
    }
  })
})

const visibleImageRows = computed(() =>
  showAllImages.value ? imageRows.value : imageRows.value.slice(0, IMAGE_ROWS)
)

/** What share of the album anyone looked at, and how many photos nobody did. */
const coverageSentence = computed(() => {
  const s = stats.value
  if (!s) return ''
  const viewed = Math.min(s.imagesViewed, s.imagesInAlbum)
  const share = Math.round((viewed / s.imagesInAlbum) * 100)
  const never = s.imagesInAlbum - viewed
  if (never === 0) return `Every photo was looked at full screen at least once.`
  return `Visitors looked at ${share}% of the album up close. ${never.toLocaleString()} ${
    never === 1 ? 'photo was' : 'photos were'
  } never opened.`
})

onMounted(async () => {
  album.value = await loadAlbumById(numericId.value)
  await load()
})

async function load() {
  loading.value = true
  error.value = null
  try {
    stats.value = await getAlbumStatistics(numericId.value)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error.value = `Could not load analytics: ${message}`
  } finally {
    loading.value = false
  }
}

async function togglePaused() {
  if (!stats.value) return
  const nextPaused = !stats.value.analyticsPaused
  saving.value = true
  try {
    await setAnalyticsPaused(numericId.value, nextPaused)
    stats.value = { ...stats.value, analyticsPaused: nextPaused }
    success(nextPaused ? 'Counting paused.' : 'Counting resumed.')
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Could not change counting: ${message}`)
  } finally {
    saving.value = false
  }
}

async function handleReset() {
  const confirmed = await confirmDialog(
    'Reset analytics for this album?\n\nEvery recorded visit, page view, filter change, audio play and photo view will be deleted. Your photos are not affected.\n\nThis cannot be undone.',
    { type: 'danger', confirmText: 'Reset analytics' }
  )
  if (!confirmed) return

  saving.value = true
  try {
    await resetAlbumAnalytics(numericId.value)
    await load()
    success('Analytics reset.')
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Could not reset analytics: ${message}`)
  } finally {
    saving.value = false
  }
}
</script>
