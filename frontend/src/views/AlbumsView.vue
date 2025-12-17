<template>
  <div class="album-overview">
    <header
      v-if="isLoggedIn"
      class="main-header"
    >
      <div class="header-left">
        <h1 class="app-title">
          Picz
        </h1>
        <div class="header-stats">
          <div class="stats-item">
            <span>📁</span>
            <span>{{ albums.length }} albums</span>
          </div>
        </div>
      </div>

      <div class="header-right">
        <div class="action-buttons">
          <button
            class="btn-primary create-album-btn"
            @click="showCreateAlbum = !showCreateAlbum"
          >
            ➕ New Album
          </button>
          <button
            v-tooltip="'Manage Tags'"
            class="btn-icon"
            @click="showManageTags = !showManageTags"
          >
            🏷️
          </button>
          <button
            v-tooltip="'Manage Languages'"
            class="btn-icon"
            @click="showManageLanguages = !showManageLanguages"
          >
            🌐
          </button>
          <button
            v-tooltip="'Target Album'"
            class="btn-icon"
            @click="showTargetAlbumSettings = !showTargetAlbumSettings"
          >
            📱
          </button>
        </div>

        <div class="user-menu">
          <button
            v-tooltip="'Profile & Settings'"
            class="btn-icon"
            @click="goToProfile"
          >
            👤
          </button>
        </div>
      </div>
    </header>
    <div
      v-if="isLoggedIn && showCreateAlbum"
      class="album-create-form"
    >
      <h3>Create New Album</h3>
      <input
        v-model="newAlbumName"
        placeholder="Album name (required)"
        class="album-input"
      >
      <input
        v-model="newAlbumDescription"
        placeholder="Description (optional)"
        class="album-input"
      >
      <div class="form-actions">
        <button
          class="btn-primary"
          @click="handleCreateAlbum"
        >
          Create
        </button>
        <button
          class="btn-secondary"
          @click="cancelCreateAlbum"
        >
          Cancel
        </button>
      </div>
    </div>
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
      v-if="isLoggedIn && loading"
      class="loading"
    >
      Loading albums...
    </div>
    <div
      v-else-if="isLoggedIn && error"
      class="error"
    >
      {{ error }}
    </div>
    <div
      v-else-if="isLoggedIn && albums.length === 0"
      class="empty-state"
    >
      <h2>No albums yet</h2>
      <p>Create your first album to start organizing photos</p>
    </div>
    <div
      v-else-if="isLoggedIn"
      class="albums-grid"
    >
      <AlbumCard
        v-for="album in albums"
        :key="album.id"
        :album="album"
        :can-delete="isLoggedIn"
        @click="handleOpenAlbum(album)"
        @delete="handleDeleteAlbum"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
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
const { albums, loading, error, loadAlbums, createAlbum, deleteAlbum } = useAlbums()
const { availableTags, loadTags } = useTags()
const { error: showError } = useNotifications()
const { confirm: confirmDialog } = useConfirm()

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

async function handleDeleteAlbum(albumId: number) {
  const album = albums.value.find(a => a.id === albumId)
  if (!album) return

  let confirmMessage: string
  if (album.fileCount === 0 || !album.fileCount) {
    confirmMessage = `Delete "${album.name}"?\n\nThis album is empty and will be permanently deleted.`
  } else {
    confirmMessage = `Delete "${album.name}"?\n\n⚠️ WARNING: This album contains ${album.fileCount} photo${album.fileCount !== 1 ? 's' : ''}.\nAll photos in this album will be permanently deleted!\n\nThis action cannot be undone.`
  }

  const confirmed = await confirmDialog(confirmMessage, {
    type: 'danger',
    confirmText: 'Delete Album'
  })

  if (!confirmed) {
    return
  }

  try {
    await deleteAlbum(albumId)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Error deleting album: ${message}`)
  }
}
</script>
