<template>
  <div class="target-album-panel">
    <h3>Target Album for Uploads</h3>

    <div class="info-text">
      <p>Select the default album where new photos will be uploaded from the iOS app.</p>
    </div>

    <div class="album-selection">
      <div
        v-if="loading"
        class="loading-state"
      >
        Loading albums...
      </div>

      <div
        v-else
        class="album-select-wrapper"
      >
        <label
          for="target-album"
          class="album-label"
        >Upload photos to:</label>
        <select
          id="target-album"
          v-model="selectedAlbumId"
          class="album-select"
          :disabled="updating || albums.length === 0"
        >
          <option :value="null">
            ⏸ Pause Sync
          </option>
          <option
            v-for="album in albums"
            :key="album.id"
            :value="album.id"
          >
            {{ album.name }}
            <span v-if="album.fileCount">({{ album.fileCount }} photos)</span>
          </option>
        </select>

        <div class="form-actions">
          <button
            class="btn-secondary"
            @click="emit('close')"
          >
            Close
          </button>
          <button
            class="btn-primary save-btn"
            :disabled="updating || selectedAlbumId === currentTargetAlbumId"
            @click="handleSaveTargetAlbum"
          >
            {{ updating ? 'Saving...' : 'Save' }}
          </button>
        </div>
      </div>

      <div
        v-if="albums.length === 0 && !loading"
        class="no-albums-message"
      >
        No albums available. Create an album first.
      </div>
    </div>

    <div
      v-if="error"
      class="error-message"
    >
      {{ error }}
    </div>
    <div
      v-if="success"
      class="success-message"
      role="status"
    >
      {{ success }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { useSettings } from '@/composables/useSettings'
import { useAlbums } from '@/composables/useAlbums'
import { useApi } from '@/composables/useApi'

const emit = defineEmits(['close'])


const {
  targetAlbumId,
  loadTargetAlbum,
  updateTargetAlbum
} = useSettings()

const { albums, loadAlbums } = useAlbums()

const selectedAlbumId = ref<number | null>(null)
const currentTargetAlbumId = ref<number | null>(null)
const loading = ref(true)
const updating = ref(false)
const error = ref<string | null>(null)
const success = ref<string | null>(null)

// Watch for changes in the composable value
watch(targetAlbumId, (newValue) => {
  selectedAlbumId.value = newValue
  currentTargetAlbumId.value = newValue
})

onMounted(async () => {
  loading.value = true
  try {
    // Load albums and target album in parallel
    await Promise.all([
      loadAlbums(),
      loadTargetAlbum()
    ])

    // Set initial selection
    selectedAlbumId.value = targetAlbumId.value
    currentTargetAlbumId.value = targetAlbumId.value
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error.value = `Failed to load: ${message}`
  } finally {
    loading.value = false
  }
})

async function handleSaveTargetAlbum() {
  updating.value = true
  error.value = null
  success.value = null

  try {
    if (selectedAlbumId.value === null) {
      // User selected "Pause Sync" - clear target album on server
      await clearTargetAlbum()
      currentTargetAlbumId.value = null
      success.value = 'Sync paused successfully!'
    } else {
      // User selected an album
      await updateTargetAlbum(selectedAlbumId.value)
      currentTargetAlbumId.value = selectedAlbumId.value
      success.value = 'Target album updated successfully!'
    }
    setTimeout(() => {
      success.value = null
    }, 3000)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error.value = `Failed to update: ${message}`
    // Revert selection on error
    selectedAlbumId.value = currentTargetAlbumId.value
  } finally {
    updating.value = false
  }
}

async function clearTargetAlbum() {
  const { apiUrl, fetchWithAuth } = useApi()

  const response = await fetchWithAuth(`${apiUrl}/api/settings/target-album`, {
    method: 'DELETE'
  })

  const data = await response.json()

  if (!response.ok || !data.success) {
    throw new Error(data.message || 'Failed to clear target album')
  }
}
</script>
