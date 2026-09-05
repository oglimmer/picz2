<template>
  <div class="albums-page">
    <!--
      The masthead carries identity, one line of live state, and the account. Nothing here is
      a toolbar button: the destination is a sentence you can click, the rest are words in a menu.
    -->
    <header class="picz-header">
      <h1 class="brand-wordmark">
        Picz
      </h1>

      <div
        v-if="albums.length > 0 && destinationLoaded"
        class="receiving"
      >
        <span
          class="receiving-dot"
          :class="uploadTarget ? 'receiving-dot--live' : 'receiving-dot--paused'"
        />
        <span class="receiving-label">
          {{ uploadTarget ? 'Phone uploads to' : 'Phone uploads' }}
        </span>
        <MenuButton role="listbox">
          <template #trigger="{ open, toggle }">
            <button
              class="receiving-value"
              :class="{ 'receiving-value--paused': !uploadTarget }"
              aria-haspopup="listbox"
              :aria-expanded="open"
              @click="toggle"
            >
              <span class="receiving-name">{{ uploadTarget ? uploadTarget.name : 'Paused' }}</span>
              <svg
                class="chev"
                width="9"
                height="9"
                viewBox="0 0 10 10"
                fill="none"
                stroke="currentColor"
                stroke-width="1.6"
              >
                <path d="M2 4l3 3 3-3" />
              </svg>
            </button>
          </template>

          <template #default="{ close }">
            <p class="popover-head">
              Send phone photos to
            </p>
            <div class="popover-scroll">
              <button
                v-for="album in albums"
                :key="album.id"
                class="menu-item"
                :class="{ 'menu-item--on': album.id === targetAlbumId }"
                role="option"
                :aria-selected="album.id === targetAlbumId"
                :disabled="savingDestination"
                @click="close(); chooseDestination(album)"
              >
                <span class="menu-item-label">{{ album.name }}</span>
                <span class="menu-item-count">{{ (album.fileCount || 0).toLocaleString() }}</span>
                <svg
                  v-if="album.id === targetAlbumId"
                  class="menu-check"
                  width="13"
                  height="13"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2.5"
                >
                  <path d="M20 6L9 17l-5-5" />
                </svg>
              </button>
            </div>
            <div class="popover-sep" />
            <button
              class="menu-item"
              :disabled="savingDestination || !uploadTarget"
              @click="close(); pauseUploads()"
            >
              <span class="menu-item-label">Pause uploads</span>
            </button>
          </template>
        </MenuButton>
      </div>

      <AccountMenu>
        <template #default="{ close }">
          <p class="popover-head">
            Library
          </p>
          <button
            class="menu-item"
            :class="{ 'menu-item--on': showManageTags }"
            role="menuitem"
            @click="close(); openPanel('tags')"
          >
            <span class="menu-item-label">Tags</span>
          </button>
          <!-- The two language names are instance-wide and only ROLE_ADMIN may rename them
               (D75), so the entry is hidden rather than shown as a field that answers 403. -->
          <button
            v-if="isAdmin"
            class="menu-item"
            :class="{ 'menu-item--on': showManageLanguages }"
            role="menuitem"
            @click="close(); openPanel('languages')"
          >
            <span class="menu-item-label">Narration languages</span>
          </button>
        </template>
      </AccountMenu>
    </header>

    <!-- The shelf: what the archive holds, then the controls that act on it. -->
    <div
      v-if="albums.length > 0"
      class="shelf"
    >
      <p class="shelf-count">
        <strong>{{ albums.length }}</strong>&nbsp;{{ albums.length === 1 ? 'album' : 'albums' }}<span
          class="shelf-dot"
        >·</span><strong>{{ totalFrames.toLocaleString() }}</strong>&nbsp;{{ totalFrames === 1 ? 'frame' : 'frames' }}
      </p>
      <span class="shelf-rule" />
      <div class="shelf-controls">
        <GridSizePicker v-model="albumSize" />
        <button
          class="new-album-btn"
          @click="showCreateAlbum = !showCreateAlbum"
        >
          <svg
            width="11"
            height="11"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
          >
            <line
              x1="12"
              y1="5"
              x2="12"
              y2="19"
            />
            <line
              x1="5"
              y1="12"
              x2="19"
              y2="12"
            />
          </svg>
          <span>New album</span>
        </button>
      </div>
    </div>

    <Transition name="panel-slide">
      <div
        v-if="showCreateAlbum"
        class="create-panel"
      >
        <h2 class="create-panel-title">
          New album
        </h2>
        <div class="create-panel-fields">
          <input
            ref="newAlbumInput"
            v-model="newAlbumName"
            placeholder="Album title"
            class="create-input"
            @keyup.enter="handleCreateAlbum"
            @keyup.esc="cancelCreateAlbum"
          >
          <input
            v-model="newAlbumDescription"
            placeholder="Description (optional)"
            class="create-input"
            @keyup.enter="handleCreateAlbum"
            @keyup.esc="cancelCreateAlbum"
          >
          <!-- Only worth a row of the form once the user has storage of their own; with just the
               instance default there is nothing to choose. -->
          <label
            v-if="storageBackends.length > 1"
            class="create-field"
          >
            <span class="create-field-label">Store photos in</span>
            <select
              v-model="newAlbumStorageBackendId"
              class="create-input"
            >
              <option
                v-for="backend in storageBackends"
                :key="backend.id"
                :value="backend.id"
              >
                {{ backend.name }}{{ backend.systemDefault ? ' (default)' : '' }}
              </option>
            </select>
            <span class="create-field-hint">This cannot be changed later.</span>
          </label>
        </div>
        <div class="create-panel-actions">
          <button
            class="btn-create"
            :disabled="!newAlbumName.trim()"
            @click="handleCreateAlbum"
          >
            Create album
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
      v-if="isLoggedIn && isAdmin && showManageLanguages"
      @close="showManageLanguages = false"
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
          Nothing archived yet
        </p>
        <p class="empty-hint">
          Make an album and your phone has somewhere to put photos.
        </p>
        <button
          class="new-album-btn"
          @click="showCreateAlbum = true"
        >
          <svg
            width="11"
            height="11"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
          >
            <line
              x1="12"
              y1="5"
              x2="12"
              y2="19"
            />
            <line
              x1="5"
              y1="12"
              x2="19"
              y2="12"
            />
          </svg>
          <span>New album</span>
        </button>
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
        :is-deleting="deletingAlbumId === album.id"
        :is-upload-target="album.id === targetAlbumId"
        @click="handleOpenAlbum(album)"
        @delete="handleDeleteAlbum"
        @duplicate="handleDuplicateAlbum"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useAlbums } from '../composables/useAlbums'
import { useTags } from '../composables/useTags'
import { useSettings } from '../composables/useSettings'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import AlbumCard from '../components/AlbumCard.vue'
import AccountMenu from '../components/AccountMenu.vue'
import MenuButton from '../components/MenuButton.vue'
import GridSizePicker, { type GridSize } from '../components/GridSizePicker.vue'
import TagManager from '../components/TagManager.vue'
import LanguageManager from '../components/LanguageManager.vue'
import { useStorageBackends } from '../composables/useStorageBackends'
import type { Album } from '@/types'

const router = useRouter()
const { isLoggedIn, isAdmin } = useAuth()
const { albums, loading, error, loadAlbums, createAlbum, deleteAlbum, duplicateAlbum } = useAlbums()
const { availableTags, loadTags } = useTags()
const { backends: storageBackends, loadBackends } = useStorageBackends()
const { targetAlbumId, loadTargetAlbum, updateTargetAlbum, clearTargetAlbum } = useSettings()
const { error: showError, info, success: showSuccess, removeNotification } = useNotifications()
const deletingAlbumId = ref<number | null>(null)
const { confirm: confirmDialog } = useConfirm()

const albumSize = ref<GridSize>((localStorage.getItem('albumGridSize') as GridSize) || 'small')
watch(albumSize, v => localStorage.setItem('albumGridSize', v))

const showCreateAlbum = ref(false)
const showManageTags = ref(false)
const showManageLanguages = ref(false)
const newAlbumName = ref('')
const newAlbumDescription = ref('')
const newAlbumInput = ref<HTMLInputElement | null>(null)
// null = the instance's own storage. Reset after each create so the next album starts from the
// default rather than inheriting a one-off choice.
const newAlbumStorageBackendId = ref<number | null>(null)

// The line says "Paused" when nothing is set, so don't render it until the setting has
// actually arrived — otherwise a fast /api/albums flashes a false alarm.
const destinationLoaded = ref(false)
const savingDestination = ref(false)

/** The album the iOS app is currently uploading into, or null while sync is paused. */
const uploadTarget = computed(() => albums.value.find(a => a.id === targetAlbumId.value) ?? null)
const totalFrames = computed(() => albums.value.reduce((sum, a) => sum + (a.fileCount || 0), 0))

onMounted(async () => {
  if (isLoggedIn.value) {
    await Promise.all([
      loadAlbums(),
      loadTags(),
      loadTargetAlbum().finally(() => { destinationLoaded.value = true }),
    ])
  }
})

function openPanel(panel: 'tags' | 'languages') {
  if (panel === 'tags') {
    showManageLanguages.value = false
    showManageTags.value = !showManageTags.value
  } else {
    showManageTags.value = false
    showManageLanguages.value = !showManageLanguages.value
  }
}

async function chooseDestination(album: Album) {
  if (album.id === targetAlbumId.value) return

  savingDestination.value = true
  try {
    await updateTargetAlbum(album.id)
    showSuccess(`Phone uploads now go to "${album.name}".`)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Could not change the upload destination: ${message}`)
  } finally {
    savingDestination.value = false
  }
}

async function pauseUploads() {
  savingDestination.value = true
  try {
    await clearTargetAlbum()
    showSuccess('Phone uploads paused.')
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    showError(`Could not pause uploads: ${message}`)
  } finally {
    savingDestination.value = false
  }
}

function handleOpenAlbum(album: Album) {
  router.push({ name: 'Album', params: { albumId: album.id.toString() } })
}

async function handleCreateAlbum() {
  if (!newAlbumName.value.trim()) return
  try {
    await createAlbum(
      newAlbumName.value,
      newAlbumDescription.value,
      newAlbumStorageBackendId.value,
    )
    newAlbumName.value = ''
    newAlbumDescription.value = ''
    newAlbumStorageBackendId.value = defaultStorageBackendId()
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
  newAlbumStorageBackendId.value = defaultStorageBackendId()
}

/** The instance's own storage, which the API always lists first. Null until the list arrives. */
function defaultStorageBackendId(): number | null {
  return storageBackends.value.find(b => b.systemDefault)?.id ?? null
}

watch(showCreateAlbum, async open => {
  if (!open) return
  // Fetched when the panel opens rather than on mount: most visits never create an album, and
  // the picker is the only thing that needs the list.
  if (storageBackends.value.length === 0) {
    await loadBackends()
    newAlbumStorageBackendId.value = defaultStorageBackendId()
  }
  await nextTick()
  newAlbumInput.value?.focus()
})

async function handleDuplicateAlbum(albumId: number) {
  const album = albums.value.find(a => a.id === albumId)
  if (!album) return

  const photoCount = album.fileCount || 0
  let confirmMessage = `Duplicate "${album.name}"?`
  if (photoCount > 0) {
    confirmMessage += `\n\nThe copy gets the same ${photoCount} photo${photoCount !== 1 ? 's' : ''} and the same tags.`
  } else {
    confirmMessage += '\n\nThe album is empty, so the copy starts empty too.'
  }
  // The copy is always a draft, even when the source is live — say so, or the missing
  // public link on the new card reads as a bug.
  confirmMessage += '\n\nThe copy is not published.'

  const confirmed = await confirmDialog(confirmMessage, {
    type: 'info',
    confirmText: 'Duplicate Album'
  })

  if (!confirmed) return

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

  if (albumId === targetAlbumId.value) {
    confirmMessage += '\n\nYour phone uploads here, so sync will pause until you pick another album.'
  }

  const confirmed = await confirmDialog(confirmMessage, {
    type: 'danger',
    confirmText: 'Delete Album'
  })

  if (!confirmed) return

  deletingAlbumId.value = albumId
  const toastId = info(`Deleting "${album.name}"…`, 0)
  try {
    await deleteAlbum(albumId)
    removeNotification(toastId)
    showSuccess(`"${album.name}" deleted.`)
    // The server clears the setting with the album; keep the masthead honest.
    if (albumId === targetAlbumId.value) await loadTargetAlbum()
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    removeNotification(toastId)
    showError(`Error deleting album: ${message}`)
  } finally {
    deletingAlbumId.value = null
  }
}
</script>
