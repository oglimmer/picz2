<template>
  <div class="albums-page">
    <header class="picz-header">
      <div class="header-brand">
        <h1 class="brand-wordmark">Picz</h1>
      </div>
      <div class="header-actions">
        <button
          class="icon-btn"
          :class="{ 'icon-btn--active': showManageTags }"
          title="Manage Tags"
          @click="showManageTags = !showManageTags"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M20.59 13.41l-7.17 7.17a2 2 0 01-2.83 0L2 12V2h10l8.59 8.59a2 2 0 010 2.82z"/>
            <line x1="7" y1="7" x2="7.01" y2="7"/>
          </svg>
        </button>
        <button
          class="icon-btn"
          :class="{ 'icon-btn--active': showManageLanguages }"
          title="Manage Languages"
          @click="showManageLanguages = !showManageLanguages"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <circle cx="12" cy="12" r="10"/>
            <line x1="2" y1="12" x2="22" y2="12"/>
            <path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/>
          </svg>
        </button>
        <button
          class="icon-btn"
          :class="{ 'icon-btn--active': showTargetAlbumSettings }"
          title="Target Album Settings"
          @click="showTargetAlbumSettings = !showTargetAlbumSettings"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <rect x="5" y="2" width="14" height="20" rx="2" ry="2"/>
            <line x1="12" y1="18" x2="12.01" y2="18"/>
          </svg>
        </button>
        <button
          class="icon-btn"
          title="Profile & Settings"
          @click="goToProfile"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/>
            <circle cx="12" cy="7" r="4"/>
          </svg>
        </button>
        <button
          class="new-album-btn"
          @click="showCreateAlbum = !showCreateAlbum"
        >
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <line x1="12" y1="5" x2="12" y2="19"/>
            <line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
          <span>New Album</span>
        </button>
      </div>
    </header>

    <div class="header-divider">
      <div class="divider-line" />
      <span class="album-count-badge">
        {{ albums.length }}&nbsp;{{ albums.length === 1 ? 'album' : 'albums' }}
      </span>
      <div class="divider-line" />
      <div class="grid-size-picker">
        <button
          v-for="size in (['small', 'medium', 'large'] as const)"
          :key="size"
          class="grid-size-btn"
          :class="{ 'grid-size-btn--active': albumSize === size }"
          :title="`${size.charAt(0).toUpperCase() + size.slice(1)} thumbnails`"
          @click="albumSize = size"
        >
          <svg v-if="size === 'small'" width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
            <rect x="0" y="0" width="6" height="6" rx="1"/>
            <rect x="8" y="0" width="6" height="6" rx="1"/>
            <rect x="0" y="8" width="6" height="6" rx="1"/>
            <rect x="8" y="8" width="6" height="6" rx="1"/>
          </svg>
          <svg v-else-if="size === 'medium'" width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
            <rect x="0" y="0" width="6" height="14" rx="1"/>
            <rect x="8" y="0" width="6" height="14" rx="1"/>
          </svg>
          <svg v-else width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
            <rect x="0" y="0" width="14" height="14" rx="1"/>
          </svg>
        </button>
      </div>
    </div>

    <Transition name="panel-slide">
      <div
        v-if="showCreateAlbum"
        class="create-panel"
      >
        <h2 class="create-panel-title">
          New Album
        </h2>
        <div class="create-panel-fields">
          <input
            v-model="newAlbumName"
            placeholder="Album title"
            class="create-input"
            @keyup.enter="handleCreateAlbum"
          >
          <input
            v-model="newAlbumDescription"
            placeholder="Description (optional)"
            class="create-input"
          >
        </div>
        <div class="create-panel-actions">
          <button
            class="btn-create"
            @click="handleCreateAlbum"
          >
            Create
          </button>
          <button
            class="btn-cancel"
            @click="cancelCreateAlbum"
          >
            Cancel
          </button>
        </div>
      </div>
    </Transition>

    <TagManager
      v-if="isLoggedIn && showManageTags"
      :tags="availableTags"
      @close="showManageTags = false"
    />
    <LanguageManager
      v-if="isLoggedIn && showManageLanguages"
      @close="showManageLanguages = false"
    />
    <TargetAlbumSettings
      v-if="isLoggedIn && showTargetAlbumSettings"
      @close="showTargetAlbumSettings = false"
    />

    <div
      v-if="loading"
      class="status-loading"
    >
      Loading archive…
    </div>

    <div
      v-else-if="error"
      class="status-error"
    >
      {{ error }}
    </div>

    <div
      v-else-if="albums.length === 0"
      class="empty-state"
    >
      <div class="empty-inner">
        <svg
          width="52"
          height="52"
          viewBox="0 0 52 52"
          fill="none"
        >
          <rect
            x="1.5"
            y="1.5"
            width="49"
            height="49"
            rx="2"
            stroke="currentColor"
            stroke-width="1"
            stroke-dasharray="5 4"
          />
          <line
            x1="26"
            y1="16"
            x2="26"
            y2="36"
            stroke="currentColor"
            stroke-width="1.2"
          />
          <line
            x1="16"
            y1="26"
            x2="36"
            y2="26"
            stroke="currentColor"
            stroke-width="1.2"
          />
        </svg>
        <p class="empty-title">
          No albums yet
        </p>
        <p class="empty-hint">
          Create your first album to begin
        </p>
      </div>
    </div>

    <div
      v-else
      class="archive-grid"
      :class="`archive-grid--${albumSize}`"
    >
      <AlbumCard
        v-for="(album, idx) in albums"
        :key="album.id"
        :album="album"
        :tile-index="idx"
        :can-delete="isLoggedIn"
        :can-duplicate="isLoggedIn"
        @click="handleOpenAlbum(album)"
        @delete="handleDeleteAlbum"
        @duplicate="handleDuplicateAlbum"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useAlbums } from '../composables/useAlbums'
import { useTags } from '../composables/useTags'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import AlbumCard from '../components/AlbumCard.vue'
import TagManager from '../components/TagManager.vue'
import LanguageManager from '../components/LanguageManager.vue'
import TargetAlbumSettings from '../components/TargetAlbumSettings.vue'
import type { Album } from '@/types'

const router = useRouter()
const { isLoggedIn } = useAuth()
const { albums, loading, error, loadAlbums, createAlbum, deleteAlbum, duplicateAlbum } = useAlbums()
const { availableTags, loadTags } = useTags()
const { error: showError } = useNotifications()
const { confirm: confirmDialog } = useConfirm()

type GridSize = 'small' | 'medium' | 'large'
const albumSize = ref<GridSize>((localStorage.getItem('albumGridSize') as GridSize) || 'small')
watch(albumSize, v => localStorage.setItem('albumGridSize', v))

const showCreateAlbum = ref(false)
const showManageTags = ref(false)
const showManageLanguages = ref(false)
const showTargetAlbumSettings = ref(false)
const newAlbumName = ref('')
const newAlbumDescription = ref('')

onMounted(async () => {
  if (isLoggedIn.value) {
    await loadAlbums()
    await loadTags()
  }
})

function handleOpenAlbum(album: Album) {
  router.push({ name: 'Album', params: { albumId: album.id.toString() } })
}

function goToProfile() {
  router.push({ name: 'Profile' })
}

async function handleCreateAlbum() {
  try {
    await createAlbum(newAlbumName.value, newAlbumDescription.value)
    newAlbumName.value = ''
    newAlbumDescription.value = ''
    showCreateAlbum.value = false
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Error creating album: ${message}`)
  }
}

function cancelCreateAlbum() {
  showCreateAlbum.value = false
  newAlbumName.value = ''
  newAlbumDescription.value = ''
}

async function handleDuplicateAlbum(albumId: number) {
  try {
    await duplicateAlbum(albumId)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Error duplicating album: ${message}`)
  }
}

async function handleDeleteAlbum(albumId: number) {
  const album = albums.value.find(a => a.id === albumId)
  if (!album) return

  let confirmMessage: string
  if (album.fileCount === 0 || !album.fileCount) {
    confirmMessage = `Delete "${album.name}"?\n\nThis album is empty and will be permanently deleted.`
  } else {
    confirmMessage = `Delete "${album.name}"?\n\nThis album contains ${album.fileCount} photo${album.fileCount !== 1 ? 's' : ''}. All photos will be permanently deleted.\n\nThis cannot be undone.`
  }

  const confirmed = await confirmDialog(confirmMessage, {
    type: 'danger',
    confirmText: 'Delete Album'
  })

  if (!confirmed) return

  try {
    await deleteAlbum(albumId)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Error deleting album: ${message}`)
  }
}
</script>
