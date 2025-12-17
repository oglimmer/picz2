<template>
  <div
    class="album-gallery"
    :class="{ 'presentation-mode': presentationMode }"
  >
    <!-- Minimal Header -->
    <div
      v-if="!presentationMode"
      class="gallery-header-minimal"
    >
      <div class="header-top-bar">
        <button
          class="back-link"
          @click="goBack"
        >
          ← Back to Albums
        </button>
        <div
          v-if="isLoggedIn"
          class="header-actions"
        >
          <button
            class="action-link"
            @click="togglePresentation"
          >
            Present
          </button>
          <button
            class="action-link"
            @click="copyPresentationUrl"
          >
            Share
          </button>
          <button
            class="action-link action-delete"
            @click="handleDeleteAlbum"
          >
            Delete
          </button>
          <span class="divider">|</span>
          <button
            class="action-link"
            @click="goToProfile"
          >
            👤 Profile
          </button>
        </div>
      </div>

      <div class="album-header-content">
        <div class="title-and-meta">
          <EditableTitle
            :title="album?.name || 'Loading...'"
            :can-edit="isLoggedIn && !presentationMode"
            title-tag="h1"
            @update:title="handleUpdateAlbumTitle"
          />
          <div class="album-meta">
            <span class="meta-item">{{ files.length }} photos</span>
            <span class="meta-dot">•</span>
            <span class="meta-item">{{ formattedTotalSize }}</span>
          </div>
        </div>

        <div
          v-if="!presentationMode"
          class="album-description-minimal"
        >
          <div
            v-if="!isEditingDescription"
            class="description-view"
          >
            <p
              v-if="album?.description"
              class="description-text-minimal"
            >
              {{ album.description }}
            </p>
            <button
              v-else-if="isLoggedIn"
              class="add-description-btn"
              @click="startEditDescription"
            >
              + Add description
            </button>
            <button
              v-if="isLoggedIn && album?.description"
              class="edit-description-link"
              @click="startEditDescription"
            >
              Edit
            </button>
          </div>
          <div
            v-else
            class="description-edit"
          >
            <textarea
              ref="descriptionInput"
              v-model="editedDescription"
              class="description-textarea"
              placeholder="Describe this album..."
              rows="2"
              @keyup.esc="cancelEditDescription"
              @keydown.enter.meta="saveDescription"
              @keydown.enter.ctrl="saveDescription"
            />
            <div class="description-actions">
              <button
                class="btn-save-small"
                @click="saveDescription"
              >
                Save
              </button>
              <button
                class="btn-cancel-link"
                @click="cancelEditDescription"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>

        <!-- Analytics Section -->
        <div
          v-if="isLoggedIn && !presentationMode"
          class="analytics-section"
        >
          <button
            class="analytics-toggle"
            @click="toggleAnalytics"
          >
            <span class="toggle-icon">{{ showAnalytics ? '▼' : '▶' }}</span>
            Analytics
            <span
              v-if="!showAnalytics && analyticsStats"
              class="analytics-preview"
            >
              ({{ analyticsStats.uniqueVisitors }} visitors, {{ analyticsStats.totalEvents }} events)
            </span>
          </button>

          <div
            v-if="showAnalytics"
            class="analytics-content"
          >
            <div class="analytics-header">
              <button
                class="refresh-button"
                @click="loadAnalyticsStats"
                :disabled="loadingAnalytics"
                title="Refresh analytics data"
              >
                <span class="refresh-icon">↻</span>
                Refresh
              </button>
            </div>
            <div
              v-if="loadingAnalytics"
              class="analytics-loading"
            >
              Loading analytics...
            </div>
            <div
              v-else-if="analyticsStats"
              class="analytics-stats"
            >
              <div class="stats-grid">
                <div class="stat-card">
                  <div class="stat-value">
                    {{ analyticsStats.uniqueVisitors }}
                  </div>
                  <div class="stat-label">
                    Unique Visitors
                  </div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">
                    {{ analyticsStats.pageViews }}
                  </div>
                  <div class="stat-label">
                    Page Views
                  </div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">
                    {{ analyticsStats.filterChanges }}
                  </div>
                  <div class="stat-label">
                    Filter Changes
                  </div>
                </div>
                <div class="stat-card">
                  <div class="stat-value">
                    {{ analyticsStats.audioPlays }}
                  </div>
                  <div class="stat-label">
                    Audio Plays
                  </div>
                </div>
              </div>

              <div
                v-if="Object.keys(analyticsStats.filterTagCounts).length > 0"
                class="filter-stats"
              >
                <h3>Popular Filter Tags</h3>
                <div class="filter-tag-list">
                  <div
                    v-for="(count, tag) in analyticsStats.filterTagCounts"
                    :key="tag"
                    class="filter-tag-item"
                  >
                    <span class="filter-tag-name">{{ tag }}</span>
                    <span class="filter-tag-count">{{ count }} events</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Presentation Mode Header -->
    <div
      v-else-if="presentationMode"
      class="gallery-header"
    >
      <div class="gallery-nav">
        <div class="album-header-info">
          <EditableTitle
            :title="album?.name || 'Loading...'"
            :can-edit="false"
            title-tag="h2"
            @update:title="handleUpdateAlbumTitle"
          />
        </div>
      </div>
      <div class="gallery-actions">
        <button
          v-if="isLoggedIn"
          class="exit-presentation-btn"
          @click="togglePresentation"
        >
          ✕ Exit Presentation
        </button>
      </div>
    </div>

    <!-- Presentation mode filter -->
    <div
      v-if="presentationMode"
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
        v-if="!isInRecordingMode && !isPlaying"
        class="recording-controls"
      >
        <div
          v-if="isLoggedIn"
          class="language-selector"
        >
          <label for="language-select">Language:</label>
          <select
            id="language-select"
            v-model="selectedLanguage"
          >
            <option value="language1">
              {{ language1Name }}
            </option>
            <option value="language2">
              {{ language2Name }}
            </option>
          </select>
        </div>
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
        <button
          v-if="isLoggedIn && !hasRecordingForLanguage(selectedTag, selectedLanguage)"
          class="audio-btn"
          :title="`Start audio recording slideshow in ${selectedLanguage === 'language1' ? language1Name : language2Name}`"
          @click="handleStartRecording"
        >
          🎤 Record
        </button>
        <button
          v-if="isLoggedIn && hasRecordingForLanguage(selectedTag, 'language1')"
          class="delete-recording-btn"
          :title="`Delete ${language1Name} recording for ${selectedTag ? 'this filter' : 'all images'}`"
          @click="handleDeleteRecording('language1')"
        >
          🗑️ Delete {{ language1Name }}
        </button>
        <button
          v-if="isLoggedIn && hasRecordingForLanguage(selectedTag, 'language2')"
          class="delete-recording-btn"
          :title="`Delete ${language2Name} recording for ${selectedTag ? 'this filter' : 'all images'}`"
          @click="handleDeleteRecording('language2')"
        >
          🗑️ Delete {{ language2Name }}
        </button>
      </div>
      <div
        v-if="isInRecordingMode"
        class="recording-status"
      >
        <span class="recording-indicator">🔴 Recording</span>
        <span>{{ formattedRecordingDuration }}</span>
      </div>
    </div>

    <!-- Regular mode controls -->
    <div
      v-if="!presentationMode && isLoggedIn"
      class="controls"
    >
      <div class="left-controls">
        <button
          class="refresh-btn"
          @click="handleRefresh"
        >
          🔄 Refresh
        </button>
        <button
          class="upload-btn"
          title="Upload photos to this album"
          @click="triggerFileUpload"
        >
          📤 Upload Files
        </button>
        <input
          ref="fileInput"
          type="file"
          multiple
          accept="image/*,video/*"
          style="display: none"
          @change="handleFileUpload"
        >
        <button
          class="reorder-btn"
          title="Reorder files by numbers in filename"
          @click="handleReorderByFilename"
        >
          🔢 Reorder by Filename
        </button>
        <button
          class="reorder-btn"
          title="Reorder files by EXIF date (photo taken date)"
          @click="handleReorderByExif"
        >
          📷 Reorder by EXIF
        </button>
      </div>

      <div class="filter-controls">
        <label for="tag-filter">Filter by tag:</label>
        <select
          id="tag-filter"
          v-model="selectedTag"
        >
          <option value="">
            All photos
          </option>
          <option
            v-for="tag in availableTags"
            :key="tag.id"
            :value="tag.name"
          >
            {{ tag.name }}
          </option>
        </select>
      </div>
    </div>

    <div
      v-if="loadingFiles"
      class="loading"
    >
      Loading photos...
    </div>

    <div
      v-if="uploading"
      class="upload-progress"
    >
      <div class="upload-progress-content">
        <div class="spinner" />
        <p>Uploading {{ uploadProgress.current + 1 }} of {{ uploadProgress.total }} files...</p>
        <p
          v-if="uploadProgress.currentFileName"
          class="upload-filename"
        >
          {{ uploadProgress.currentFileName }}
        </p>
        <p class="upload-status">
          {{ uploadProgress.status }}
        </p>
      </div>
    </div>

    <div
      v-else-if="files.length === 0"
      class="empty-state"
    >
      <h2>No photos in this album</h2>
      <p>Upload photos using the macOS Share Extension</p>
    </div>

    <!-- Empty state when presentation mode and no filter selected -->
    <div
      v-else-if="presentationMode && !selectedTag && tagsUsedInAlbum.length > 0"
      class="empty-state"
    >
      <h2>Please select a tag filter</h2>
      <p>Choose a tag from the dropdown above to view photos</p>
    </div>

    <!-- Gallery -->
    <div
      v-else
      class="gallery"
      :class="{ 'presentation-gallery': presentationMode }"
    >
      <GalleryItem
        v-for="(file, index) in files"
        :key="file.id"
        :file="file"
        :available-tags="availableTags"
        :is-draggable="!presentationMode && isLoggedIn"
        :show-drag-handle="!presentationMode && isLoggedIn"
        :show-file-info="!presentationMode && isLoggedIn"
        :dragging="draggingIndex === index"
        :drag-over="dragOverIndex === index"
        @click="openLightbox"
        @delete="handleDeleteFile"
        @rotate="handleRotateImage"
        @add-tag="handleAddTag"
        @remove-tag="handleRemoveTag"
        @filter-tag="filterByTagName"
        @drag-start="(e) => handleDragStart(e, index)"
        @drag-over="(e) => handleDragOver(e, index)"
        @drag-enter="(e) => handleDragEnter(e, index)"
        @drag-leave="handleDragLeave"
        @drop="(e) => handleDrop(e, index)"
        @drag-end="handleDragEnd"
      />
    </div>

    <!-- Lightbox -->
    <Lightbox
      :file="selectedFile"
      :is-recording="isInRecordingMode"
      :is-playing="isPlaying"
      :is-paused="isPaused"
      :audio-player="audioPlayer"
      @close="closeLightbox"
      @next="navigateNext"
      @previous="navigatePrevious"
      @image-changed="handleImageChanged"
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
  </div>
</template>

<script>
import { ref, computed, watch, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useApi } from '../composables/useApi'
import { useAlbums } from '../composables/useAlbums'
import { useFiles } from '../composables/useFiles'
import { useTags } from '../composables/useTags'
import { useSettings } from '../composables/useSettings'
import { useSlideshow } from '../composables/useSlideshow'
import { useSlideshowPlayback } from '../composables/useSlideshowPlayback'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import { useAnalytics } from '../composables/useAnalytics'
import { formatBytes } from '../utils/format'
import GalleryItem from '../components/GalleryItem.vue'
import Lightbox from '../components/Lightbox.vue'
import EditableTitle from '../components/EditableTitle.vue'

export default {
  name: 'GalleryView',
  components: {
    GalleryItem,
    Lightbox,
    EditableTitle
  },
  props: {
    albumId: {
      type: [String, Number],
      required: true
    },
    presentationMode: {
      type: Boolean,
      default: false
    }
  },
  setup(props) {
    const router = useRouter()
    const { isLoggedIn, logout } = useAuth()
    const { apiUrl, fetchWithAuth } = useApi()
    const { currentAlbum, loadAlbumById, updateAlbum, deleteAlbum } = useAlbums()
    const {
      files,
      loadingFiles,
      totalSize,
      selectedTag,
      tagsUsedInAlbum,
      loadAlbumFiles,
      deleteFile,
      addTag,
      removeTag,
      reorderFiles,
      reorderByFilename,
      reorderByExif
    } = useFiles()
    const { availableTags, loadTags } = useTags()
    const { language1Name, language2Name, loadLanguageSettings } = useSettings()
    const {
      isInRecordingMode,
      uploading,
      totalDuration,
      startRecording,
      stopRecordingAndUpload,
      trackImageStart,
      cancelRecording
    } = useSlideshow()
    const {
      isPlaying,
      currentFile: playbackCurrentFile,
      recordings,
      loadRecordings,
      hasRecordings,
      startPlayback,
      stopPlayback,
      pausePlayback,
      resumePlayback,
      deleteRecording
    } = useSlideshowPlayback()
    const { success, error, warning, info } = useNotifications()
    const { confirm: confirmDialog } = useConfirm()
    const { getAlbumStatistics } = useAnalytics()

    const album = computed(() => currentAlbum.value)
    const selectedFile = ref(null)
    const draggingIndex = ref(null)
    const dragOverIndex = ref(null)
    const selectedLanguage = ref('language1')
    const audioPlayer = ref(null)
    const isPaused = ref(false)
    const controlsVisible = ref(true)
    const fileInput = ref(null)
    const uploadProgress = ref({ current: 0, total: 0, status: '' })
    const isEditingDescription = ref(false)
    const editedDescription = ref('')
    const descriptionInput = ref(null)
    const showAnalytics = ref(false)
    const loadingAnalytics = ref(false)
    const analyticsStats = ref(null)

    const formattedTotalSize = computed(() => formatBytes(totalSize.value))
    const formattedRecordingDuration = computed(() => {
      const seconds = Math.floor(totalDuration.value / 1000)
      const minutes = Math.floor(seconds / 60)
      const remainingSeconds = seconds % 60
      return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
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

    // Watch for tag changes and reload files (only in non-presentation mode)
    watch(selectedTag, () => {
      if (album.value && !props.presentationMode) {
        loadAlbumFiles(album.value.id, props.presentationMode)
      }
    })

    // Watch for playback current file changes and update lightbox
    watch(playbackCurrentFile, (newFile) => {
      if (isPlaying.value && newFile) {
        selectedFile.value = newFile
      }
    })

    // Auto-select tag when there's only one tag in presentation mode
    watch(tagsUsedInAlbum, (tags) => {
      if (props.presentationMode && tags.length === 1) {
        selectedTag.value = tags[0].name
      }
    })

    onMounted(async () => {
      // Load album data
      await loadAlbumById(parseInt(props.albumId), props.presentationMode)

      // Load tags if logged in
      if (isLoggedIn.value) {
        await loadTags()
      }

      // Load language settings
      await loadLanguageSettings()

      // Load files
      if (album.value) {
        await loadAlbumFiles(album.value.id, props.presentationMode)
      }

      // Load recordings for presentation mode
      if (props.presentationMode && album.value) {
        await loadRecordings(album.value.id)
      }
    })

    // React to prop changes when the same component instance is reused
    watch(() => props.presentationMode, async (isPresentation) => {
      // Reload files to respect presentation filtering
      if (album.value) {
        await loadAlbumFiles(album.value.id, isPresentation)
        if (isPresentation) {
          await loadRecordings(album.value.id)
        }
      }
    })

    // When navigating to a different album route, refresh album, files, and recordings
    watch(() => props.albumId, async (newAlbumId) => {
      const id = parseInt(newAlbumId)
      if (!Number.isNaN(id)) {
        await loadAlbumById(id, props.presentationMode)
        if (isLoggedIn.value) {
          await loadTags()
        }
        if (album.value) {
          await loadAlbumFiles(album.value.id, props.presentationMode)
          if (props.presentationMode) {
            await loadRecordings(album.value.id)
          }
        }
      }
    })

    function goBack() {
      router.push({ name: 'Albums' })
    }

    async function handleRefresh() {
      if (album.value) {
        await loadAlbumFiles(album.value.id, props.presentationMode)
      }
    }

    async function handleUpdateAlbumTitle(newTitle) {
      if (!album.value) return

      try {
        await updateAlbum(album.value.id, {
          name: newTitle,
          description: album.value.description
        })
      } catch (err) {
        error(`Error saving album title: ${err.message}`)
      }
    }

    function startEditDescription() {
      if (!isLoggedIn.value) return
      isEditingDescription.value = true
      editedDescription.value = album.value?.description || ''
      // Focus on the textarea after it's rendered
      setTimeout(() => {
        if (descriptionInput.value) {
          descriptionInput.value.focus()
        }
      }, 50)
    }

    async function saveDescription() {
      if (!album.value) return

      try {
        await updateAlbum(album.value.id, {
          name: album.value.name,
          description: editedDescription.value
        })
        isEditingDescription.value = false
      } catch (err) {
        error(`Error saving album description: ${err.message}`)
      }
    }

    function cancelEditDescription() {
      isEditingDescription.value = false
      editedDescription.value = ''
    }

    function togglePresentation() {
      if (props.presentationMode) {
        // Exit presentation mode
        router.push({ name: 'Album', params: { albumId: props.albumId } })
      } else {
        // Enter presentation mode
        router.push({ name: 'AlbumPresentation', params: { albumId: props.albumId } })
      }
    }

    function copyPresentationUrl() {
      if (!album.value) return

      try {
        const token = album.value.shareToken
        if (!token) {
          warning('Share token not available for this album')
          return
        }

        // Use the public route URL
        const url = new URL(window.location.origin)
        url.pathname = `/public/album/${token}`
        const shareUrl = url.toString()

        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(shareUrl).then(() => {
            success('Presentation link copied to clipboard!')
          }).catch(() => {
            window.open(shareUrl, '_blank')
          })
        } else {
          window.open(shareUrl, '_blank')
        }
      } catch (err) {
        console.error('Error creating share link:', err)
        error('Error creating share link')
      }
    }

    async function handleDeleteFile(fileId) {
      const confirmed = await confirmDialog('Are you sure you want to delete this photo?', {
        type: 'danger',
        confirmText: 'Delete'
      })

      if (!confirmed) {
        return
      }

      try {
        await deleteFile(fileId)
      } catch (err) {
        error(`Error deleting file: ${err.message}`)
      }
    }

    async function handleRotateImage(fileId) {
      try {
        info('Rotating image...')
        const response = await fetchWithAuth(`${apiUrl}/api/files/${fileId}/rotate`, {
          method: 'POST'
        })

        if (!response.ok) {
          throw new Error('Failed to rotate image')
        }

        // Reload files to show the rotated image
        if (album.value) {
          await loadAlbumFiles(album.value.id, props.presentationMode)
        }

        success('Image rotated successfully!')
      } catch (err) {
        error(`Error rotating image: ${err.message}`)
      }
    }

    async function handleAddTag(fileId, tagName) {
      try {
        await addTag(fileId, tagName)
      } catch (err) {
        error(`Error adding tag: ${err.message}`)
      }
    }

    async function handleRemoveTag(fileId, tagName) {
      try {
        await removeTag(fileId, tagName)
      } catch (err) {
        error(`Error removing tag: ${err.message}`)
      }
    }

    function filterByTagName(tagName) {
      selectedTag.value = tagName
    }

    async function handleReorderByFilename() {
      if (!album.value) return

      const confirmed = await confirmDialog('Reorder all files in this album by filename numbers? This will sort files based on numbers found in their filenames.', {
        type: 'warning',
        confirmText: 'Reorder'
      })

      if (!confirmed) {
        return
      }

      try {
        const count = await reorderByFilename(album.value.id)
        await loadAlbumFiles(album.value.id, props.presentationMode)
        success(`Successfully reordered ${count || 'all'} files!`)
      } catch (err) {
        error(`Error reordering files: ${err.message}`)
      }
    }

    async function handleReorderByExif() {
      if (!album.value) return

      const confirmed = await confirmDialog('Reorder all files in this album by EXIF date? This will sort files based on the date the photo was taken (from EXIF metadata). Files without EXIF dates will be sorted by upload date.', {
        type: 'warning',
        confirmText: 'Reorder'
      })

      if (!confirmed) {
        return
      }

      try {
        const count = await reorderByExif(album.value.id)
        await loadAlbumFiles(album.value.id, props.presentationMode)
        success(`Successfully reordered ${count || 'all'} files by EXIF date!`)
      } catch (err) {
        error(`Error reordering files by EXIF: ${err.message}`)
      }
    }

    // Drag and drop handlers
    function handleDragStart(event, index) {
      draggingIndex.value = index
      event.dataTransfer.effectAllowed = 'move'
      event.dataTransfer.setData('text/html', event.target.innerHTML)
    }

    function handleDragOver(event, index) {
      event.preventDefault()
      event.dataTransfer.dropEffect = 'move'
      dragOverIndex.value = index
    }

    function handleDragEnter(event, index) {
      event.preventDefault()
      dragOverIndex.value = index
    }

    function handleDragLeave() {
      // Visual feedback only
    }

    async function handleDrop(event, dropIndex) {
      event.preventDefault()
      event.stopPropagation()

      const dragIndex = draggingIndex.value

      if (dragIndex === null || dragIndex === dropIndex) {
        draggingIndex.value = null
        dragOverIndex.value = null
        return
      }

      // Reorder the files array
      const newFiles = [...files.value]
      const [draggedFile] = newFiles.splice(dragIndex, 1)
      newFiles.splice(dropIndex, 0, draggedFile)

      // Update local state immediately for smooth UX
      files.value = newFiles

      draggingIndex.value = null
      dragOverIndex.value = null

      // Send new order to server
      const fileIds = newFiles.map(f => f.id)
      try {
        await reorderFiles(fileIds)
      } catch (err) {
        // Revert on error
        if (album.value) {
          await loadAlbumFiles(album.value.id, props.presentationMode)
        }
        error(`Error reordering files: ${err.message}`)
      }
    }

    function handleDragEnd() {
      draggingIndex.value = null
      dragOverIndex.value = null
    }

    // Slideshow Recording
    async function handleStartRecording() {
      if (files.value.length === 0) {
        warning('No images available to start recording')
        return
      }

      try {
        // Start recording with first filtered file
        const firstFile = files.value[0]
        await startRecording(album.value.id, selectedTag.value || null, selectedLanguage.value, firstFile)

        // Open lightbox with first image
        selectedFile.value = firstFile
      } catch (err) {
        console.error('Failed to start recording:', err)
        error('Failed to start recording: ' + err.message)
      }
    }

    // Slideshow Playback
    async function handleStartPlayback(language) {
      if (files.value.length === 0) {
        warning('No images available to play')
        return
      }

      try {
        // Get recording for this tag and language
        const recording = getRecordingForLanguage(selectedTag.value || null, language)

        if (!recording) {
          warning('No recording found for this filter and language')
          return
        }

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

    async function handleDeleteRecording(language) {
      // Get the recording for this tag and language
      const recording = getRecordingForLanguage(selectedTag.value || null, language)
      if (!recording) return

      const languageName = language === 'language1' ? language1Name.value : language2Name.value
      const filterDescription = selectedTag.value ? `"${selectedTag.value}"` : 'all images'

      const confirmed = await confirmDialog(`Delete the ${languageName} recording for ${filterDescription}? This action cannot be undone.`, {
        type: 'danger',
        confirmText: 'Delete'
      })

      if (!confirmed) {
        return
      }

      try {
        await deleteRecording(recording.id)
        // Reload recordings to update UI
        if (album.value) {
          await loadRecordings(album.value.id)
        }
        success('Recording deleted successfully!')
      } catch (err) {
        console.error('Failed to delete recording:', err)
        error('Failed to delete recording: ' + err.message)
      }
    }

    function handleImageChanged(file) {
      if (isInRecordingMode.value) {
        trackImageStart(file)
      }
    }

    // Lightbox
    function openLightbox(file) {
      selectedFile.value = file
    }

    async function closeLightbox() {
      // If recording, stop and upload
      if (isInRecordingMode.value) {
        try {
          await stopRecordingAndUpload()
          // Reload recordings so UI reflects the newly saved recording
          if (album.value) {
            await loadRecordings(album.value.id)
          }
          success('Recording saved successfully!')
        } catch (err) {
          console.error('Failed to save recording:', err)
          const shouldDiscard = await confirmDialog('Failed to save recording. Do you want to discard it?', {
            type: 'warning',
            confirmText: 'Discard'
          })

          if (shouldDiscard) {
            cancelRecording()
          } else {
            // Don't close lightbox, let user try again
            return
          }
        }
      }

      // If playing back a recording, stop audio when lightbox closes
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
      const nextFile = files.value[nextIndex]
      selectedFile.value = nextFile

      // Track image change if recording
      if (isInRecordingMode.value) {
        trackImageStart(nextFile)
      }
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
      const previousFile = files.value[previousIndex]
      selectedFile.value = previousFile

      // Track image change if recording
      if (isInRecordingMode.value) {
        trackImageStart(previousFile)
      }
    }

    function goToProfile() {
      router.push({ name: 'Profile' })
    }

    async function handleDeleteAlbum() {
      if (!album.value) return

      const fileCount = files.value.length

      let confirmMessage
      if (fileCount === 0) {
        confirmMessage = `Delete "${album.value.name}"?\n\nThis album is empty and will be permanently deleted.`
      } else {
        confirmMessage = `Delete "${album.value.name}"?\n\n⚠️ WARNING: This album contains ${fileCount} photo${fileCount !== 1 ? 's' : ''}.\nAll photos in this album will be permanently deleted!\n\nThis action cannot be undone.`
      }

      const confirmed = await confirmDialog(confirmMessage, {
        type: 'danger',
        confirmText: 'Delete Album'
      })

      if (!confirmed) {
        return
      }

      try {
        await deleteAlbum(album.value.id)
        // Redirect to albums after successful deletion
        router.push({ name: 'Albums' })
      } catch (err) {
        error(`Error deleting album: ${err.message}`)
      }
    }

    // Upload handlers
    function triggerFileUpload() {
      if (fileInput.value) {
        fileInput.value.click()
      }
    }

    async function handleFileUpload(event) {
      const selectedFiles = Array.from(event.target.files || [])
      if (selectedFiles.length === 0) return
      if (!album.value) {
        warning('No album selected')
        return
      }

      uploading.value = true
      uploadProgress.value = {
        current: 0,
        total: selectedFiles.length,
        status: 'Preparing upload...',
        currentFileName: ''
      }

      let successCount = 0
      let errorCount = 0
      const errors = []

      try {
        // Upload files one at a time (sequentially)
        for (let i = 0; i < selectedFiles.length; i++) {
          const file = selectedFiles[i]
          uploadProgress.value.current = i
          uploadProgress.value.currentFileName = file.name
          uploadProgress.value.status = `Uploading ${file.name}...`

          const formData = new FormData()
          formData.append('file', file)
          formData.append('albumId', album.value.id)

          try {
            const response = await fetchWithAuth(`${apiUrl}/api/upload`, {
              method: 'POST',
              body: formData
            })

            const data = await response.json()

            if (response.ok && data.success) {
              successCount++
              uploadProgress.value.current = i + 1
            } else {
              errorCount++
              errors.push(`${file.name}: ${data.message || 'Upload failed'}`)
              console.error(`Upload failed for ${file.name}:`, data.message)
            }
          } catch (err) {
            errorCount++
            errors.push(`${file.name}: ${err.message}`)
            console.error(`Upload error for ${file.name}:`, err)
          }
        }

        // Show results
        uploadProgress.value.status = 'Upload complete!'

        // Reload the album files to show the new uploads
        await loadAlbumFiles(album.value.id, props.presentationMode)

        if (successCount > 0 && errorCount === 0) {
          success(`Successfully uploaded ${successCount} file(s)!`)
        } else if (successCount > 0 && errorCount > 0) {
          warning(`Uploaded ${successCount} file(s), ${errorCount} failed. Check console for details.`)
          console.error('Upload errors:', errors)
        } else {
          error(`All uploads failed. Check console for details.`)
          console.error('Upload errors:', errors)
        }
      } catch (err) {
        console.error('Unexpected upload error:', err)
        error(`Error uploading files: ${err.message}`)
      } finally {
        uploading.value = false
        uploadProgress.value = { current: 0, total: 0, status: '', currentFileName: '' }
        // Reset the file input so the same files can be selected again
        if (fileInput.value) {
          fileInput.value.value = ''
        }
      }
    }

    // Analytics
    async function toggleAnalytics() {
      showAnalytics.value = !showAnalytics.value

      // Load analytics when opening
      if (showAnalytics.value && !analyticsStats.value) {
        await loadAnalyticsStats()
      }
    }

    async function loadAnalyticsStats() {
      if (!album.value) return

      loadingAnalytics.value = true
      try {
        analyticsStats.value = await getAlbumStatistics(album.value.id)
      } catch (err) {
        console.error('Error loading analytics:', err)
        error('Failed to load analytics')
      } finally {
        loadingAnalytics.value = false
      }
    }

    return {
      isLoggedIn,
      album,
      files,
      loadingFiles,
      formattedTotalSize,
      selectedTag,
      tagsUsedInAlbum,
      availableTags,
      selectedFile,
      draggingIndex,
      dragOverIndex,
      isInRecordingMode,
      isPlaying,
      isPaused,
      formattedRecordingDuration,
      recordings,
      hasRecordings,
      selectedLanguage,
      language1Name,
      language2Name,
      hasRecordingForLanguage,
      audioPlayer,
      fileInput,
      uploading,
      uploadProgress,
      isEditingDescription,
      editedDescription,
      descriptionInput,
      showAnalytics,
      loadingAnalytics,
      analyticsStats,
      toggleAnalytics,
      loadAnalyticsStats,
      goBack,
      handleRefresh,
      handleUpdateAlbumTitle,
      startEditDescription,
      saveDescription,
      cancelEditDescription,
      togglePresentation,
      copyPresentationUrl,
      handleDeleteFile,
      handleRotateImage,
      handleAddTag,
      handleRemoveTag,
      filterByTagName,
      handleReorderByFilename,
      handleReorderByExif,
      handleDragStart,
      handleDragOver,
      handleDragEnter,
      handleDragLeave,
      handleDrop,
      handleDragEnd,
      handleStartRecording,
      handleStartPlayback,
      handlePauseResume,
      handleStopPlayback,
      handleDeleteRecording,
      handleImageChanged,
      openLightbox,
      closeLightbox,
      navigateNext,
      navigatePrevious,
      goToProfile,
      handleDeleteAlbum,
      triggerFileUpload,
      handleFileUpload
    }
  }
}
</script>
