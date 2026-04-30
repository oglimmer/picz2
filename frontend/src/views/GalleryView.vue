<template>
  <div
    class="album-gallery"
    :class="{ 'presentation-mode': presentationMode }"
  >
    <!-- Full-page overlay while album deletion is in progress -->
    <div
      v-if="isDeletingAlbum"
      class="album-deleting-overlay"
    >
      <svg
        class="album-deleting-spinner"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
      >
        <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
      </svg>
      <p class="album-deleting-message">Deleting album and all photos…</p>
      <p class="album-deleting-sub">This may take a moment.</p>
    </div>
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
            :disabled="isDeletingAlbum"
            @click="handleDeleteAlbum"
          >
            {{ isDeletingAlbum ? 'Deleting…' : 'Delete' }}
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
              <button
                v-if="analyticsStats"
                class="pause-button"
                :class="{ 'paused': analyticsStats.analyticsPaused }"
                @click="handleToggleAnalyticsPaused"
                :title="analyticsStats.analyticsPaused ? 'Resume analytics counting' : 'Pause analytics counting'"
              >
                {{ analyticsStats.analyticsPaused ? '▶ Resume' : '⏸ Pause' }}
              </button>
              <button
                v-if="analyticsStats"
                class="reset-button"
                @click="handleResetAnalytics"
                title="Delete all analytics data for this album"
              >
                ✕ Reset
              </button>
            </div>
            <div
              v-if="analyticsStats && analyticsStats.analyticsPaused"
              class="analytics-paused-notice"
            >
              Analytics counting is paused — no new events are being recorded.
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
        <button
          class="duplicates-btn"
          :class="{ 'duplicates-btn-active': duplicateFilterActive }"
          :title="duplicateFilterActive ? 'Exit duplicate view' : 'Show only files with duplicate names'"
          @click="toggleDuplicateFilter"
        >
          {{ duplicateFilterActive ? '✕ Exit Duplicates' : '🔍 Find Duplicates' }}
        </button>
        <button
          v-if="duplicateFilterActive"
          class="delete-selected-btn"
          :disabled="selectedForDeletion.size === 0"
          title="Delete all selected files"
          @click="handleDeleteSelected"
        >
          🗑️ Delete Selected ({{ selectedForDeletion.size }})
        </button>
        <button
          class="reorder-mode-btn"
          :class="{ 'reorder-mode-btn-active': reorderModeActive }"
          :title="reorderModeActive ? 'Exit reorder mode' : 'Select and mass-move images'"
          @click="toggleReorderMode"
        >
          {{ reorderModeActive ? '✕ Exit Reorder' : '🔀 Reorder' }}
        </button>
        <button
          v-if="reorderModeActive"
          class="move-to-top-btn"
          :disabled="selectedForReorder.size === 0"
          title="Move selected images to the top"
          @click="handleMoveSelectedToTop"
        >
          ⬆ Move to Top ({{ selectedForReorder.size }})
        </button>
        <button
          class="tag-manage-btn"
          :class="{ 'tag-manage-btn-active': tagPickerOpen }"
          title="Choose which tags are available in this album"
          @click="toggleTagPicker"
        >
          🏷️ Manage Album Tags
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
            v-for="tag in enabledAlbumTags"
            :key="tag.id"
            :value="tag.name"
          >
            {{ tag.name }}
          </option>
        </select>
      </div>

      <div class="grid-size-picker">
        <button
          v-for="size in ['small', 'medium', 'large']"
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

    <div
      v-if="!presentationMode && isLoggedIn && tagPickerOpen"
      class="tag-picker-panel"
    >
      <div class="tag-picker-header">
        <strong>Enable tags for this album</strong>
        <span class="tag-picker-hint">
          Only enabled tags can be applied to photos or used as filters here.
        </span>
      </div>
      <div
        v-if="availableTags.length === 0"
        class="tag-picker-empty"
      >
        No tags defined yet. Create tags from the Albums overview first.
      </div>
      <ul
        v-else
        class="tag-picker-list"
      >
        <li
          v-for="tag in togglableTags"
          :key="tag.id"
          class="tag-picker-item"
        >
          <label>
            <input
              type="checkbox"
              :checked="pickerSelectedTagIds.has(tag.id)"
              @change="togglePickerTag(tag.id)"
            >
            <span>{{ tag.name }}</span>
          </label>
        </li>
      </ul>
      <div class="tag-picker-actions">
        <button
          class="btn-save-small"
          :disabled="savingEnabledTags"
          @click="saveEnabledTags"
        >
          {{ savingEnabledTags ? 'Saving…' : 'Save' }}
        </button>
        <button
          class="btn-cancel-link"
          @click="closeTagPicker"
        >
          Cancel
        </button>
      </div>
    </div>

    <div
      v-if="!presentationMode && isLoggedIn && !tagPickerOpen && enabledAlbumTags.length === 0 && availableTags.length > 0"
      class="tag-picker-notice"
    >
      No tags are enabled for this album yet. Click "Manage Album Tags" to enable tags.
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

    <!-- Empty state when duplicate filter is active but no duplicates found -->
    <div
      v-else-if="duplicateFilterActive && displayedFiles.length === 0"
      class="empty-state"
    >
      <h2>No duplicate filenames found</h2>
      <p>All files in this album have unique names.</p>
    </div>

    <!-- Gallery -->
    <div
      v-else
      class="gallery"
      :class="[{ 'presentation-gallery': presentationMode }, !presentationMode && `gallery--${albumSize}`]"
    >
      <GalleryItem
        v-for="(file, index) in displayedFiles"
        :key="`${file.id}:${file.publicToken}`"
        :file="file"
        :available-tags="enabledAlbumTags"
        :is-draggable="!presentationMode && isLoggedIn && !duplicateFilterActive && !reorderModeActive"
        :show-drag-handle="!presentationMode && isLoggedIn && !duplicateFilterActive && !reorderModeActive && !selectionActive"
        :show-file-info="!presentationMode && isLoggedIn"
        :dragging="draggingIndex === index"
        :drag-over="dragOverIndex === index"
        :selectable="!presentationMode && isLoggedIn"
        :selected="reorderModeActive ? selectedForReorder.has(file.id) : duplicateFilterActive ? selectedForDeletion.has(file.id) : selectedFileIds.has(file.id)"
        :selection-active="!presentationMode && (selectionActive || duplicateFilterActive || reorderModeActive)"
        :bulk-select="duplicateFilterActive || reorderModeActive"
        :select-variant="reorderModeActive ? 'reorder' : 'delete'"
        :move-target="reorderModeActive && selectedForReorder.size > 0 && !selectedForReorder.has(file.id)"
        @click="openLightbox"
        @delete="handleDeleteFile"
        @rotate="handleRotateImage"
        @add-tag="handleAddTag"
        @remove-tag="handleRemoveTag"
        @filter-tag="filterByTagName"
        @toggle-select="(fileId, shiftKey) => handleToggleSelect(fileId, index, shiftKey)"
        @move-here="handleMoveSelectedAfter"
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

    <!-- Bulk tag bar (shown when images are selected) -->
    <BulkTagBar
      v-if="!presentationMode && isLoggedIn"
      :selected-count="selectedFileIds.size"
      :available-tags="enabledAlbumTags"
      :frequent-tags="frequentTags"
      @add-tag="handleBulkAddTag"
      @clear="clearSelection"
    />
  </div>
</template>

<script>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useApi } from '../composables/useApi'
import { useAlbums } from '../composables/useAlbums'
import { useFiles } from '../composables/useFiles'
import { useProcessingPoller } from '../composables/useProcessingPoller'
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
import BulkTagBar from '../components/BulkTagBar.vue'

export default {
  name: 'GalleryView',
  components: {
    GalleryItem,
    Lightbox,
    EditableTitle,
    BulkTagBar
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
    // Polls /api/assets/{id}/status for any file that arrived from the backend with
    // processingStatus != DONE (typical right after a fresh upload). When a file's status
    // flips to a terminal state, the file ref is mutated so GalleryItem rerenders the
    // <img> instead of the spinner placeholder.
    const processingPoller = useProcessingPoller(files)
    const {
      availableTags,
      enabledAlbumTags,
      loadTags,
      loadEnabledAlbumTags,
      setEnabledAlbumTags,
      clearEnabledAlbumTags
    } = useTags()
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
    const { success, error, warning, info, removeNotification } = useNotifications()
    const { confirm: confirmDialog } = useConfirm()
    const { getAlbumStatistics, resetAlbumAnalytics, setAnalyticsPaused } = useAnalytics()

    const isDeletingAlbum = ref(false)
    const album = computed(() => currentAlbum.value)
    const albumSize = ref(localStorage.getItem('galleryGridSize') || 'small')
    watch(albumSize, v => localStorage.setItem('galleryGridSize', v))

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
    const duplicateFilterActive = ref(false)
    const selectedForDeletion = ref(new Set())
    const reorderModeActive = ref(false)
    const selectedForReorder = ref(new Set())
    const tagPickerOpen = ref(false)
    const pickerSelectedTagIds = ref(new Set())
    const savingEnabledTags = ref(false)

    const EXCLUDED_DUPLICATE_NAME = 'fullsizerender.heic'

    function isExcludedFromDuplicates(file) {
      const name = file.originalName || file.filename || ''
      return name.toLowerCase() === EXCLUDED_DUPLICATE_NAME
    }

    const displayedFiles = computed(() => {
      if (!duplicateFilterActive.value) return files.value
      const nameCounts = new Map()
      for (const file of files.value) {
        if (isExcludedFromDuplicates(file)) continue
        const key = file.originalName || file.filename
        nameCounts.set(key, (nameCounts.get(key) || 0) + 1)
      }
      return files.value.filter(f => {
        if (isExcludedFromDuplicates(f)) return false
        const key = f.originalName || f.filename
        return (nameCounts.get(key) || 0) > 1
      })
    })

    function toggleDuplicateFilter() {
      if (duplicateFilterActive.value) {
        duplicateFilterActive.value = false
        selectedForDeletion.value = new Set()
        return
      }
      if (reorderModeActive.value) {
        reorderModeActive.value = false
        selectedForReorder.value = new Set()
      }
      duplicateFilterActive.value = true
      const seen = new Set()
      const toSelect = new Set()
      for (const file of files.value) {
        if (isExcludedFromDuplicates(file)) continue
        const key = file.originalName || file.filename
        if (seen.has(key)) {
          toSelect.add(file.id)
        } else {
          seen.add(key)
        }
      }
      selectedForDeletion.value = toSelect
    }

    function toggleReorderMode() {
      if (reorderModeActive.value) {
        reorderModeActive.value = false
        selectedForReorder.value = new Set()
        return
      }
      if (duplicateFilterActive.value) {
        duplicateFilterActive.value = false
        selectedForDeletion.value = new Set()
      }
      reorderModeActive.value = true
      selectedForReorder.value = new Set()
    }

    function toggleReorderSelection(fileId) {
      const next = new Set(selectedForReorder.value)
      if (next.has(fileId)) {
        next.delete(fileId)
      } else {
        next.add(fileId)
      }
      selectedForReorder.value = next
    }

    async function persistReorder(newFiles, successMessage) {
      files.value = newFiles
      selectedForReorder.value = new Set()
      const fileIds = newFiles.map(f => f.id)
      try {
        await reorderFiles(fileIds)
        if (successMessage) success(successMessage)
      } catch (err) {
        if (album.value) {
          await loadAlbumFiles(album.value.id, props.presentationMode)
        }
        error(`Error reordering files: ${err.message}`)
      }
    }

    async function handleMoveSelectedAfter(targetFileId) {
      const selectedIds = selectedForReorder.value
      if (selectedIds.size === 0) return
      if (selectedIds.has(targetFileId)) return

      const currentFiles = [...files.value]
      const selectedList = currentFiles.filter(f => selectedIds.has(f.id))
      const remaining = currentFiles.filter(f => !selectedIds.has(f.id))

      const targetIndex = remaining.findIndex(f => f.id === targetFileId)
      if (targetIndex === -1) return

      const newFiles = [
        ...remaining.slice(0, targetIndex + 1),
        ...selectedList,
        ...remaining.slice(targetIndex + 1)
      ]

      const count = selectedList.length
      await persistReorder(newFiles, `Moved ${count} file${count !== 1 ? 's' : ''}.`)
    }

    async function handleMoveSelectedToTop() {
      const selectedIds = selectedForReorder.value
      if (selectedIds.size === 0) return

      const currentFiles = [...files.value]
      const selectedList = currentFiles.filter(f => selectedIds.has(f.id))
      const remaining = currentFiles.filter(f => !selectedIds.has(f.id))

      const newFiles = [...selectedList, ...remaining]
      const count = selectedList.length
      await persistReorder(newFiles, `Moved ${count} file${count !== 1 ? 's' : ''} to top.`)
    }

    function toggleFileSelection(fileId) {
      const next = new Set(selectedForDeletion.value)
      if (next.has(fileId)) {
        next.delete(fileId)
      } else {
        next.add(fileId)
      }
      selectedForDeletion.value = next
    }

    async function handleDeleteSelected() {
      const ids = Array.from(selectedForDeletion.value)
      if (ids.length === 0) return

      const confirmed = await confirmDialog(
        `Delete ${ids.length} selected file${ids.length !== 1 ? 's' : ''}? This action cannot be undone.`,
        { type: 'danger', confirmText: 'Delete' }
      )
      if (!confirmed) return

      let successCount = 0
      let errorCount = 0
      for (const id of ids) {
        try {
          await deleteFile(id)
          successCount++
        } catch (err) {
          errorCount++
          console.error(`Failed to delete file ${id}:`, err)
        }
      }

      selectedForDeletion.value = new Set()

      if (errorCount === 0) {
        success(`Successfully deleted ${successCount} file${successCount !== 1 ? 's' : ''}!`)
      } else if (successCount > 0) {
        warning(`Deleted ${successCount} file${successCount !== 1 ? 's' : ''}, ${errorCount} failed.`)
      } else {
        error('Failed to delete selected files.')
      }

      if (displayedFiles.value.length === 0) {
        duplicateFilterActive.value = false
      }
    }

    // Multi-select state
    const selectedFileIds = ref(new Set())
    const lastSelectedIndex = ref(null)
    const selectionActive = computed(() => selectedFileIds.value.size > 0)
    const SYSTEM_TAGS = new Set(['no_tag', 'all'])
    const togglableTags = computed(() =>
      availableTags.value.filter(t => !SYSTEM_TAGS.has(t.name))
    )
    const enabledTagNames = computed(() => new Set(enabledAlbumTags.value.map(t => t.name)))
    const frequentTags = computed(() =>
      [...tagsUsedInAlbum.value]
        .filter(t => enabledTagNames.value.has(t.name))
        .sort((a, b) => b.count - a.count)
        .slice(0, 6)
    )

    function toggleTagPicker() {
      if (tagPickerOpen.value) {
        closeTagPicker()
        return
      }
      // Seed from currently enabled tags, but exclude system tags — they can't be toggled.
      pickerSelectedTagIds.value = new Set(
        enabledAlbumTags.value
          .filter(t => !SYSTEM_TAGS.has(t.name))
          .map(t => t.id)
      )
      tagPickerOpen.value = true
    }

    function closeTagPicker() {
      tagPickerOpen.value = false
      pickerSelectedTagIds.value = new Set()
    }

    function togglePickerTag(tagId) {
      const next = new Set(pickerSelectedTagIds.value)
      if (next.has(tagId)) {
        next.delete(tagId)
      } else {
        next.add(tagId)
      }
      pickerSelectedTagIds.value = next
    }

    async function saveEnabledTags() {
      if (!album.value) return
      savingEnabledTags.value = true
      try {
        await setEnabledAlbumTags(album.value.id, [...pickerSelectedTagIds.value])
        success('Album tags updated.')
        closeTagPicker()
      } catch (err) {
        error(`Error saving enabled tags: ${err.message}`)
      } finally {
        savingEnabledTags.value = false
      }
    }

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
      window.addEventListener('keydown', handleGalleryKeydown)

      // Load album data
      await loadAlbumById(parseInt(props.albumId), props.presentationMode)

      // Load tags if logged in
      if (isLoggedIn.value) {
        await loadTags()
        if (album.value && !props.presentationMode) {
          await loadEnabledAlbumTags(album.value.id)
        }
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

    // Whenever the file list changes (initial load, post-upload reload, reorder, etc),
    // hand the new entries to the poller. startOne() is idempotent, so files that are
    // already being polled are not re-armed.
    watch(files, (newFiles) => {
      processingPoller.watchFiles(newFiles)
    }, { deep: false })

    onUnmounted(() => {
      window.removeEventListener('keydown', handleGalleryKeydown)
      clearEnabledAlbumTags()
      processingPoller.stopAll()
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
        closeTagPicker()
        clearEnabledAlbumTags()
        await loadAlbumById(id, props.presentationMode)
        if (isLoggedIn.value) {
          await loadTags()
          if (album.value && !props.presentationMode) {
            await loadEnabledAlbumTags(album.value.id)
          }
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

        // Mirror the api-side state flip locally so GalleryItem's thumbnailReady computed flips
        // to false and the "Processing…" spinner replaces the thumbnail while the worker rotates.
        // The poll loop below keeps it in sync (QUEUED → PROCESSING → DONE).
        const target = files.value.find(f => f.id === fileId)
        if (target) {
          target.processingStatus = 'QUEUED'
        }

        // Rotate is async since Phase 4.5: api returns 202 after enqueuing a worker job. Poll
        // /api/assets/{id}/status until DONE before reloading, otherwise the gallery would show
        // stale derivatives. Cap the wait so a stuck worker surfaces as a user-visible error
        // instead of an infinite spinner.
        const pollDeadline = Date.now() + 60_000
        while (Date.now() < pollDeadline) {
          await new Promise(resolve => setTimeout(resolve, 1000))
          const statusRes = await fetchWithAuth(`${apiUrl}/api/assets/${fileId}/status`)
          if (!statusRes.ok) {
            throw new Error('Failed to read rotation status')
          }
          const status = await statusRes.json()
          if (target && status.processingStatus) {
            target.processingStatus = status.processingStatus
          }
          if (status.processingStatus === 'DONE') {
            break
          }
          if (status.processingStatus === 'FAILED' || status.processingStatus === 'DEAD_LETTER') {
            throw new Error(status.error || 'Rotation failed on the worker')
          }
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

    function handleToggleSelect(fileId, index, shiftKey) {
      if (reorderModeActive.value) {
        toggleReorderSelection(fileId)
        return
      }
      if (duplicateFilterActive.value) {
        toggleFileSelection(fileId)
        return
      }
      const ids = new Set(selectedFileIds.value)
      if (shiftKey && lastSelectedIndex.value !== null) {
        const lo = Math.min(lastSelectedIndex.value, index)
        const hi = Math.max(lastSelectedIndex.value, index)
        for (let i = lo; i <= hi; i++) {
          ids.add(files.value[i].id)
        }
      } else {
        if (ids.has(fileId)) {
          ids.delete(fileId)
        } else {
          ids.add(fileId)
        }
        lastSelectedIndex.value = index
      }
      selectedFileIds.value = ids
    }

    function clearSelection() {
      selectedFileIds.value = new Set()
      lastSelectedIndex.value = null
    }

    function selectAll() {
      selectedFileIds.value = new Set(files.value.map(f => f.id))
    }

    async function handleBulkAddTag(tagName) {
      if (!tagName || selectedFileIds.value.size === 0) return
      const ids = [...selectedFileIds.value]
      let count = 0
      for (const fileId of ids) {
        try {
          await addTag(fileId, tagName)
          count++
        } catch (err) {
          console.error(`Error tagging file ${fileId}:`, err)
        }
      }
      if (count > 0) success(`Tagged ${count} photo${count !== 1 ? 's' : ''} with "${tagName}"`)
    }

    function handleGalleryKeydown(e) {
      if (!isLoggedIn.value || selectedFile.value) return
      if (e.key === 'Escape' && selectionActive.value) {
        e.preventDefault()
        clearSelection()
      }
      if ((e.key === 'a' || e.key === 'A') && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        selectAll()
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

      isDeletingAlbum.value = true
      const toastId = info(`Deleting "${album.value.name}"…`, 0)
      try {
        await deleteAlbum(album.value.id)
        removeNotification(toastId)
        router.push({ name: 'Albums' })
      } catch (err) {
        removeNotification(toastId)
        isDeletingAlbum.value = false
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

    async function handleResetAnalytics() {
      if (!album.value) return
      if (!confirm('Reset all analytics data for this album? This cannot be undone.')) return
      try {
        await resetAlbumAnalytics(album.value.id)
        await loadAnalyticsStats()
        success('Analytics reset successfully')
      } catch (err) {
        console.error('Error resetting analytics:', err)
        error('Failed to reset analytics')
      }
    }

    async function handleToggleAnalyticsPaused() {
      if (!album.value || !analyticsStats.value) return
      const newPaused = !analyticsStats.value.analyticsPaused
      try {
        await setAnalyticsPaused(album.value.id, newPaused)
        analyticsStats.value = { ...analyticsStats.value, analyticsPaused: newPaused }
        success(newPaused ? 'Analytics paused' : 'Analytics resumed')
      } catch (err) {
        console.error('Error toggling analytics pause:', err)
        error('Failed to update analytics state')
      }
    }

    return {
      isLoggedIn,
      album,
      files,
      selectedFileIds,
      selectionActive,
      frequentTags,
      handleToggleSelect,
      clearSelection,
      handleBulkAddTag,
      loadingFiles,
      formattedTotalSize,
      selectedTag,
      tagsUsedInAlbum,
      availableTags,
      enabledAlbumTags,
      togglableTags,
      tagPickerOpen,
      pickerSelectedTagIds,
      savingEnabledTags,
      toggleTagPicker,
      closeTagPicker,
      togglePickerTag,
      saveEnabledTags,
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
      duplicateFilterActive,
      selectedForDeletion,
      reorderModeActive,
      selectedForReorder,
      displayedFiles,
      toggleDuplicateFilter,
      toggleFileSelection,
      handleDeleteSelected,
      toggleReorderMode,
      handleMoveSelectedAfter,
      handleMoveSelectedToTop,
      toggleAnalytics,
      loadAnalyticsStats,
      handleResetAnalytics,
      handleToggleAnalyticsPaused,
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
      isDeletingAlbum,
      handleDeleteAlbum,
      triggerFileUpload,
      handleFileUpload,
      albumSize
    }
  }
}
</script>

<style scoped>
.album-deleting-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: rgba(0, 0, 0, 0.65);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
}

.album-deleting-spinner {
  width: 48px;
  height: 48px;
  color: #fff;
  animation: spin 1s linear infinite;
}

.album-deleting-message {
  font-size: 1.1rem;
  color: #fff;
  margin: 0;
}

.album-deleting-sub {
  font-size: 0.85rem;
  color: rgba(255, 255, 255, 0.7);
  margin: 0;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
