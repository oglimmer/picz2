<template>
  <div
    class="album-gallery"
    :class="{ 'presentation-mode': presentationMode, 'map-mode': mapMode }"
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
      <p class="album-deleting-message">
        Deleting album and all photos…
      </p>
      <p class="album-deleting-sub">
        This may take a moment.
      </p>
    </div>

    <!--
      Masthead, shared with the albums page: identity, where you are, and the account. The
      album's own actions live with the album below, not up here.
    -->
    <header
      v-if="!presentationMode"
      class="picz-header"
    >
      <router-link
        to="/albums"
        class="brand-wordmark"
      >
        Picz
      </router-link>
      <div class="crumb">
        <router-link
          to="/albums"
          class="crumb-link"
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
          <span class="crumb-name">All albums</span>
        </router-link>
      </div>
      <AccountMenu v-if="isLoggedIn" />
    </header>

    <AlbumHeader
      v-if="!presentationMode"
      :album="album"
      :photo-count="files.length"
      :formatted-total-size="formattedTotalSize"
      :can-edit="isLoggedIn"
      :is-published="isPublished"
      :toggling-published="togglingPublished"
      :enabled-tag-count="enabledAlbumTags.length"
      :tag-picker-open="tagPicker.open.value"
      :duplicate-filter-active="duplicates.active.value"
      :is-deleting="isDeletingAlbum"
      @present="togglePresentation"
      @share="copyPresentationUrl"
      @toggle-published="togglePublished"
      @toggle-tag-picker="tagPicker.toggleOpen"
      @toggle-duplicates="duplicates.toggleMode"
      @delete-album="handleDeleteAlbum"
      @update-title="handleUpdateAlbumTitle"
      @update-description="handleUpdateDescription"
    />

    <!-- Presentation Mode Header -->
    <div
      v-else
      class="gallery-header"
    >
      <div class="gallery-nav">
        <div class="album-header-info">
          <EditableTitle
            :title="album?.name || 'Loading...'"
            :can-edit="false"
            title-tag="h2"
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

    <PresentationControls
      v-if="presentationMode"
      v-model:selected-tag="selectedTag"
      v-model:selected-language="recording.selectedLanguage.value"
      :tags-used-in-album="tagsUsedInAlbum"
      :language1-name="language1Name"
      :language2-name="language2Name"
      :recording-count="recordings.length"
      :has-recordings="hasRecordings"
      :has-recording-for="hasRecordingFor"
      :can-record="isLoggedIn"
      :is-recording="recording.isInRecordingMode.value"
      :is-playing="isPlaying"
      :recording-duration="recording.formattedDuration.value"
      @play="(language) => startPlayback(selectedTag, language)"
      @record="recording.start"
      @delete-recording="recording.remove"
    />

    <GalleryShelf
      v-if="!presentationMode && isLoggedIn"
      v-model:view-mode="viewMode"
      v-model:selected-tag="selectedTag"
      v-model:grid-size="albumSize"
      v-model:album-tag-name="tagAll.tagName.value"
      :view-modes="viewModes"
      :enabled-album-tags="enabledAlbumTags"
      :loading="loadingFiles"
      :reorder-mode-active="reorder.active.value"
      :album-tag-busy="tagAll.busy.value"
      :album-tag-disabled="tagAll.disabled.value"
      :album-tag-add-title="tagAll.addTitle.value"
      :album-tag-remove-title="tagAll.removeTitle.value"
      @refresh="loader.reloadFiles"
      @reorder-by-filename="handleReorderByFilename"
      @reorder-by-exif="handleReorderByExif"
      @toggle-reorder="reorder.toggleMode"
      @tag-all="tagAll.run"
      @files-picked="upload.uploadFiles"
    />

    <!-- A mode gets its own strip while it is on, instead of leaving its controls lying around. -->
    <div
      v-if="!presentationMode && isLoggedIn && reorder.active.value"
      class="mode-bar"
    >
      <span class="mode-bar-label">Arranging by hand</span>
      <span class="mode-bar-hint">
        {{ reorder.selected.value.size > 0
          ? `${reorder.selected.value.size} selected — click the gap where they should go, or move them to the top.`
          : 'Select the photos you want to move.' }}
      </span>
      <button
        class="btn"
        :disabled="reorder.selected.value.size === 0"
        @click="reorder.moveSelectedToTop"
      >
        Move to top
      </button>
      <button
        class="action-link"
        @click="reorder.toggleMode"
      >
        Done
      </button>
    </div>

    <div
      v-if="!presentationMode && isLoggedIn && duplicates.active.value"
      class="mode-bar"
    >
      <span class="mode-bar-label">Duplicate names</span>
      <span class="mode-bar-hint">
        {{ displayedFiles.length > 0
          ? `${displayedFiles.length} files share a name with another file.`
          : 'Every file in this album has a unique name.' }}
      </span>
      <button
        class="btn-danger"
        :disabled="duplicates.selected.value.size === 0"
        @click="duplicates.deleteSelected"
      >
        Delete selected ({{ duplicates.selected.value.size }})
      </button>
      <button
        class="action-link"
        @click="duplicates.toggleMode"
      >
        Done
      </button>
    </div>

    <TagPickerPanel
      v-if="!presentationMode && isLoggedIn && tagPicker.open.value"
      :tags="tagPicker.togglableTags.value"
      :selected-tag-ids="tagPicker.selectedTagIds.value"
      :saving="tagPicker.saving.value"
      @toggle="tagPicker.toggleTag"
      @save="tagPicker.save"
      @close="tagPicker.close"
    />

    <div
      v-if="!presentationMode && isLoggedIn && !tagPicker.open.value && enabledAlbumTags.length === 0 && availableTags.length > 0"
      class="tag-picker-notice"
    >
      No tags are enabled for this album yet. Enable some under Manage → Album tags.
    </div>

    <div
      v-if="loadingFiles"
      class="loading"
    >
      Loading photos...
    </div>

    <div
      v-if="upload.uploading.value"
      class="upload-progress"
    >
      <div class="upload-progress-content">
        <div class="spinner" />
        <p>Uploading {{ upload.progress.value.current + 1 }} of {{ upload.progress.value.total }} files...</p>
        <p
          v-if="upload.progress.value.currentFileName"
          class="upload-filename"
        >
          {{ upload.progress.value.currentFileName }}
        </p>
        <p class="upload-status">
          {{ upload.progress.value.status }}
        </p>
      </div>
    </div>

    <!-- Map filter: replaces the grid entirely. Fed the whole album, not `displayedFiles`,
         because the map is an alternative to tag filtering rather than a layer on top of it. -->
    <PhotoMap
      v-else-if="mapMode"
      :files="files"
      :saved-view="albumMapViewValue"
      :can-edit-view="true"
      @open="openLightbox"
      @save-view="handleSaveMapView"
      @clear-view="handleClearMapView"
    />

    <div
      v-else-if="files.length === 0"
      class="empty-state"
    >
      <div class="empty-inner">
        <p class="empty-title">
          No photos in this album
        </p>
        <p class="empty-hint">
          Use “Upload photos” above, or let your phone send them here.
        </p>
      </div>
    </div>

    <!-- Empty state when presentation mode and no filter selected -->
    <div
      v-else-if="presentationMode && !selectedTag && tagsUsedInAlbum.length > 0"
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

    <!-- Empty state when duplicate filter is active but no duplicates found -->
    <div
      v-else-if="duplicates.active.value && displayedFiles.length === 0"
      class="empty-state"
    >
      <div class="empty-inner">
        <p class="empty-title">
          No duplicate filenames found
        </p>
        <p class="empty-hint">
          All files in this album have unique names.
        </p>
      </div>
    </div>

    <!-- Presentation gallery, split into image groups (per tag) -->
    <PresentationSectionList
      v-else-if="presentationMode"
      :sections="presentationSections"
      :editable="canManageGroups"
      @edit-group="groups.openEdit"
      @delete-group="groups.remove"
    >
      <template #default="{ file, section }">
        <GalleryItem
          :file="file"
          :show-file-info="false"
          :show-drag-handle="false"
          :can-start-group="canManageGroups"
          :group-start="Boolean(groupStartingAt(file.id, selectedTag))"
          :can-end-group="canManageGroups && Boolean(section.group)"
          :group-end="Boolean(section.group) && section.group?.endFileId === file.id"
          @click="openLightbox"
          @start-group="groups.openCreate"
          @end-group="groups.toggleEnd(section.group, $event)"
        />
      </template>
    </PresentationSectionList>

    <!-- By day & region: one section per calendar day, one sub-section per place. -->
    <DayRegionSections
      v-else-if="dayRegionActive"
      :groups="dayRegionGroups"
      :grid-class="`gallery--${albumSize}`"
    >
      <template #default="{ file }">
        <GalleryItem
          :file="file"
          :available-tags="enabledAlbumTags"
          :is-draggable="false"
          :show-drag-handle="false"
          :show-file-info="isLoggedIn"
          :selectable="isLoggedIn"
          :selected="isSelected(file.id)"
          :selection-active="anySelectionActive"
          :bulk-select="duplicates.active.value || reorder.active.value"
          :select-variant="reorder.active.value ? 'reorder' : 'delete'"
          :move-target="isMoveTarget(file.id)"
          @click="openLightbox"
          @delete="handleDeleteFile"
          @rotate="handleRotateImage"
          @add-tag="handleAddTag"
          @update-caption="handleUpdateCaption"
          @remove-tag="handleRemoveTag"
          @filter-tag="filterByTagName"
          @toggle-select="(fileId, shiftKey) => handleToggleSelect(fileId, albumIndexOf(fileId), shiftKey)"
          @move-here="reorder.moveSelectedAfter"
        />
      </template>
    </DayRegionSections>

    <!-- Gallery -->
    <div
      v-else
      class="gallery"
      :class="`gallery--${albumSize}`"
    >
      <GalleryItem
        v-for="(file, index) in displayedFiles"
        :key="`${file.id}:${file.publicToken}`"
        :file="file"
        :available-tags="enabledAlbumTags"
        :is-draggable="plainGridEditable"
        :show-drag-handle="plainGridEditable && !selection.selectionActive.value"
        :show-file-info="!presentationMode && isLoggedIn"
        :dragging="reorder.draggingIndex.value === index"
        :drag-over="reorder.dragOverIndex.value === index"
        :selectable="!presentationMode && isLoggedIn"
        :selected="isSelected(file.id)"
        :selection-active="!presentationMode && anySelectionActive"
        :bulk-select="duplicates.active.value || reorder.active.value"
        :select-variant="reorder.active.value ? 'reorder' : 'delete'"
        :move-target="isMoveTarget(file.id)"
        @click="openLightbox"
        @delete="handleDeleteFile"
        @rotate="handleRotateImage"
        @add-tag="handleAddTag"
        @update-caption="handleUpdateCaption"
        @remove-tag="handleRemoveTag"
        @filter-tag="filterByTagName"
        @toggle-select="(fileId, shiftKey) => handleToggleSelect(fileId, index, shiftKey)"
        @move-here="reorder.moveSelectedAfter"
        @drag-start="(e) => reorder.onDragStart(e, index)"
        @drag-over="(e) => reorder.onDragOver(e, index)"
        @drag-enter="(e) => reorder.onDragEnter(e, index)"
        @drop="(e) => reorder.onDrop(e, index)"
        @drag-end="reorder.onDragEnd"
      />
    </div>

    <!-- Lightbox -->
    <Lightbox
      :file="selectedFile"
      :group-context="lightboxGroupContext"
      :is-recording="recording.isInRecordingMode.value"
      :is-saving="recording.savingRecording.value"
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

    <!-- Bulk tag bar (shown when images are selected) -->
    <BulkTagBar
      v-if="!presentationMode && isLoggedIn"
      :selected-count="selection.selectedFileIds.value.size"
      :available-tags="enabledAlbumTags"
      :frequent-tags="frequentTags"
      :rotatable-count="selectedRotatableIds.length"
      :busy="bulkBusy"
      :busy-label="bulkLabel"
      @add-tag="handleBulkAddTag"
      @rotate="handleBulkRotate"
      @delete-selected="handleBulkDelete"
      @clear="selection.clear"
    />

    <!-- Create / edit an image group -->
    <PresentationGroupDialog
      :show="groups.dialogOpen.value"
      :mode="groups.dialogMode.value"
      :tag="selectedTag"
      :initial-label="groups.dialogTarget.value?.label || ''"
      :initial-text="groups.dialogTarget.value?.text || ''"
      :saving="groups.dialogSaving.value"
      @save="groups.save"
      @close="groups.dialogOpen.value = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted, useTemplateRef } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '@/composables/useAuth'
import { useAlbums } from '@/composables/useAlbums'
import { useFiles } from '@/composables/useFiles'
import { useProcessingPoller } from '@/composables/useProcessingPoller'
import { useTags } from '@/composables/useTags'
import { useSettings } from '@/composables/useSettings'
import { useNotifications } from '@/composables/useNotifications'
import { useConfirm } from '@/composables/useConfirm'
import { usePresentationGroups } from '@/composables/usePresentationGroups'
import { useLightboxNavigation } from '@/composables/useLightboxNavigation'
import { usePlaybackControls } from '@/composables/usePlaybackControls'
import { useMapViewMode } from '@/composables/useMapViewMode'
import { useDayRegionView } from '@/composables/useDayRegionView'
import { useAlbumLoader } from '@/composables/gallery/useAlbumLoader'
import { useSelection } from '@/composables/gallery/useSelection'
import { useBulkActions } from '@/composables/gallery/useBulkActions'
import { useReorderMode } from '@/composables/gallery/useReorderMode'
import { useDuplicateMode } from '@/composables/gallery/useDuplicateMode'
import { useAlbumTagPicker } from '@/composables/gallery/useAlbumTagPicker'
import { useAlbumTagAll } from '@/composables/gallery/useAlbumTagAll'
import { useGroupEditing } from '@/composables/gallery/useGroupEditing'
import { useRecordingSession } from '@/composables/gallery/useRecordingSession'
import { useUploadFlow } from '@/composables/gallery/useUploadFlow'
import { formatBytes, isVideo } from '@/utils/format'
import { albumMapView, type MapView } from '@/types'
import GalleryItem from '@/components/GalleryItem.vue'
import Lightbox from '@/components/Lightbox.vue'
import EditableTitle from '@/components/EditableTitle.vue'
import BulkTagBar from '@/components/BulkTagBar.vue'
import PresentationGroupDialog from '@/components/PresentationGroupDialog.vue'
import PresentationSectionList from '@/components/PresentationSectionList.vue'
import DayRegionSections from '@/components/DayRegionSections.vue'
import PhotoMap from '@/components/PhotoMap.vue'
import AccountMenu from '@/components/AccountMenu.vue'
import AlbumHeader from '@/components/AlbumHeader.vue'
import PresentationControls from '@/components/PresentationControls.vue'
import GalleryShelf, { type ViewMode, type ViewModeOption } from '@/components/GalleryShelf.vue'
import TagPickerPanel from '@/components/TagPickerPanel.vue'
import type { GridSize } from '@/components/GridSizePicker.vue'

interface Props {
  albumId: string | number
  presentationMode?: boolean
}

const props = withDefaults(defineProps<Props>(), { presentationMode: false })

const router = useRouter()
const { isLoggedIn } = useAuth()
const { currentAlbum: album, loadAlbumById, updateAlbum, saveMapView, setPublished, deleteAlbum } =
  useAlbums()
const {
  files,
  loadingFiles,
  totalSize,
  selectedTag,
  tagsUsedInAlbum,
  loadAlbumFiles,
  deleteFile,
  rotateFile,
  addTag,
  removeTag,
  updateCaption,
  addTagToAllFiles,
  removeTagFromAllFiles,
  reorderFiles,
  reorderByFilename,
  reorderByExif
} = useFiles()
const { availableTags, enabledAlbumTags, loadTags, loadEnabledAlbumTags, setEnabledAlbumTags, clearEnabledAlbumTags } =
  useTags()
const { language1Name, language2Name, loadLanguageSettings } = useSettings()
const { success, error, warning, info, removeNotification } = useNotifications()
const { confirm } = useConfirm()
const groupsApi = usePresentationGroups()
const { loadGroups, groupStartingAt, buildSections, groupContextFor } = groupsApi

// Polls /api/assets/{id}/status for any file that arrived with processingStatus != DONE (right
// after an upload or a rotate). When it flips to a terminal state the file is mutated so the tile
// swaps its spinner for the thumbnail. The same poller waits on bulk rotates.
const poller = useProcessingPoller(files)
watch(files, (newFiles) => poller.watchFiles(newFiles))

const albumIdNumber = computed(() => Number(props.albumId))
const albumMapViewValue = computed(() => albumMapView(album.value))
const formattedTotalSize = computed(() => formatBytes(totalSize.value))

// --- Lightbox, playback, recording -------------------------------------------------------------
const { selectedFile, open: openLightbox, next: navigateNext, previous: navigatePrevious } =
  useLightboxNavigation(files, (file) => recording.trackImage(file))

const audioPlayer = useTemplateRef<HTMLAudioElement>('audioPlayer')
const { playback, isPaused, controlsVisible, startPlayback, pauseResume, stop: stopPlayback } =
  usePlaybackControls(files, selectedFile, audioPlayer)
const { isPlaying, recordings, loadRecordings, hasRecordings, hasRecordingFor, recordingFor, deleteRecording } =
  playback

const recording = useRecordingSession({
  album,
  files,
  selectedTag,
  selectedFile,
  language1Name,
  language2Name,
  loadRecordings,
  recordingFor,
  deleteRecording
})

async function closeLightbox() {
  // A recording is saved on close; the session says whether the lightbox may go.
  if (!(await recording.finishOnClose())) return
  if (isPlaying.value) {
    playback.stopPlayback()
    controlsVisible.value = true
  }
  selectedFile.value = null
}

// --- Loading -----------------------------------------------------------------------------------
const loader = useAlbumLoader({
  isLoggedIn,
  loadAlbumById,
  loadAlbumFiles,
  loadTags,
  loadEnabledAlbumTags,
  clearEnabledAlbumTags,
  loadLanguageSettings,
  loadRecordings,
  loadGroups
})

onMounted(() => {
  window.addEventListener('keydown', handleGalleryKeydown)
  void loader.load(albumIdNumber.value, props.presentationMode)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleGalleryKeydown)
  clearEnabledAlbumTags()
  poller.stopAll()
})

// The same component instance serves /album/:id and /album/:id/presentation, and a new album id.
watch([albumIdNumber, () => props.presentationMode], ([id, presentation]) => {
  if (Number.isNaN(id)) return
  tagPicker.close()
  void loader.load(id, presentation)
})

// The logged-in gallery filters on the server; presentation mode filters the loaded set itself
// (that watcher lives in useFiles).
watch(selectedTag, () => {
  if (album.value && !props.presentationMode) void loader.reloadFiles()
})

// Auto-select the tag when there is only one in presentation mode
watch(tagsUsedInAlbum, (tags) => {
  if (props.presentationMode && tags.length === 1) selectedTag.value = tags[0].name
})

// --- Grid size ---------------------------------------------------------------------------------
const albumSize = ref<GridSize>((localStorage.getItem('galleryGridSize') as GridSize) || 'small')
watch(albumSize, (v) => localStorage.setItem('galleryGridSize', v))

// --- Selection, bulk actions, modes ------------------------------------------------------------
const selection = useSelection(files)
const bulk = useBulkActions({
  deleteFile,
  rotateFile,
  addTag,
  waitForProcessing: poller.waitFor,
  reloadFiles: loader.reloadFiles
})
const reorder = useReorderMode({
  files,
  reorderFiles,
  reloadFiles: loader.reloadFiles,
  onActivate: () => {
    if (duplicates.active.value) duplicates.toggleMode()
  }
})
const duplicates = useDuplicateMode({
  files,
  deleteMany: bulk.deleteMany,
  onActivate: () => {
    if (reorder.active.value) reorder.toggleMode()
  }
})
const displayedFiles = duplicates.displayedFiles

const anySelectionActive = computed(
  () => selection.selectionActive.value || duplicates.active.value || reorder.active.value
)
const plainGridEditable = computed(
  () => !props.presentationMode && isLoggedIn.value && !duplicates.active.value && !reorder.active.value
)

function isSelected(fileId: number): boolean {
  if (reorder.active.value) return reorder.selected.value.has(fileId)
  if (duplicates.active.value) return duplicates.selected.value.has(fileId)
  return selection.selectedFileIds.value.has(fileId)
}

function isMoveTarget(fileId: number): boolean {
  return reorder.active.value && reorder.selected.value.size > 0 && !reorder.selected.value.has(fileId)
}

// Shift-select ranges are indices into the full album, and the grouped view hands out files in
// section order, so the index has to be looked up rather than read off the loop.
const albumIndexById = computed(() => new Map(files.value.map((file, index) => [file.id, index])))
function albumIndexOf(fileId: number): number {
  return albumIndexById.value.get(fileId) ?? -1
}

function handleToggleSelect(fileId: number, index: number, shiftKey?: boolean) {
  if (reorder.active.value) return reorder.toggleSelection(fileId)
  if (duplicates.active.value) return duplicates.toggleSelection(fileId)
  selection.toggle(fileId, index, shiftKey)
}

function handleGalleryKeydown(e: KeyboardEvent) {
  if (!isLoggedIn.value || selectedFile.value) return
  if (selection.handleKeydown(e)) e.preventDefault()
}

// Guards the bulk bar while a rotate/delete run is in flight; the label doubles as progress text.
const bulkBusy = ref(false)
const bulkLabel = ref('')

// Videos have no rotate job, so the bulk rotate button acts on the image subset only.
const selectedRotatableIds = computed(() =>
  files.value.filter((f) => selection.selectedFileIds.value.has(f.id) && !isVideo(f)).map((f) => f.id)
)

async function runBulk(label: string, action: () => Promise<void>) {
  if (bulkBusy.value) return
  bulkBusy.value = true
  bulkLabel.value = label
  try {
    await action()
  } finally {
    bulkBusy.value = false
    bulkLabel.value = ''
  }
}

const handleBulkAddTag = (tagName: string) =>
  bulk.tagMany([...selection.selectedFileIds.value], tagName)

const handleBulkRotate = () =>
  runBulk(`Rotating ${selectedRotatableIds.value.length}…`, () => bulk.rotateMany(selectedRotatableIds.value))

const handleBulkDelete = () =>
  runBulk(`Deleting ${selection.selectedFileIds.value.size}…`, async () => {
    const failed = await bulk.deleteMany([...selection.selectedFileIds.value])
    // Keep the ids that failed selected so the user can retry them without reselecting.
    if (failed !== null) selection.selectedFileIds.value = new Set(failed)
  })

// --- Single-photo actions ----------------------------------------------------------------------
async function handleDeleteFile(fileId: number) {
  const confirmed = await confirm('Are you sure you want to delete this photo?', {
    type: 'danger',
    confirmText: 'Delete'
  })
  if (!confirmed) return
  try {
    await deleteFile(fileId)
  } catch (err) {
    error(`Error deleting file: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

async function handleRotateImage(fileId: number) {
  info('Rotating image...')
  await bulk.rotateMany([fileId])
}

async function handleAddTag(fileId: number, tagName: string) {
  try {
    await addTag(fileId, tagName)
  } catch (err) {
    error(`Error adding tag: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

async function handleRemoveTag(fileId: number, tagName: string) {
  try {
    await removeTag(fileId, tagName)
  } catch (err) {
    error(`Error removing tag: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

async function handleUpdateCaption(fileId: number, caption: string) {
  try {
    await updateCaption(fileId, caption)
    success(caption ? 'Caption saved' : 'Caption removed')
  } catch (err) {
    error(`Error saving caption: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

function filterByTagName(tagName: string) {
  selectedTag.value = tagName
}

// --- Album tags --------------------------------------------------------------------------------
const tagPicker = useAlbumTagPicker({ album, availableTags, enabledAlbumTags, setEnabledAlbumTags })
const tagAll = useAlbumTagAll({
  album,
  files,
  selectedTag,
  enabledAlbumTags,
  addTagToAllFiles,
  removeTagFromAllFiles,
  reloadFiles: loader.reloadFiles
})

const enabledTagNames = computed(() => new Set(enabledAlbumTags.value.map((t) => t.name)))
const frequentTags = computed(() =>
  [...tagsUsedInAlbum.value]
    .filter((t) => enabledTagNames.value.has(t.name))
    .sort((a, b) => b.count - a.count)
    .slice(0, 6)
)

// --- Views: map, day & region, grid ------------------------------------------------------------
const { mapMode, mapFilterAvailable } = useMapViewMode(files, () => !props.presentationMode)
const { dayRegionGrouping, dayRegionAvailable, dayRegionActive, dayRegionGroups } = useDayRegionView(
  displayedFiles,
  () => !props.presentationMode && !mapMode.value && Boolean(selectedTag.value)
)

// Grid / Days / Map are one control over the two flags above. The map is fed the whole album, so
// a tag left set would claim to narrow something it does not: switching to it clears the tag.
const viewMode = computed<ViewMode>({
  get() {
    if (mapMode.value) return 'map'
    return dayRegionActive.value ? 'days' : 'grid'
  },
  set(value) {
    if (value === 'map') {
      mapMode.value = true
      dayRegionGrouping.value = false
      selectedTag.value = ''
      return
    }
    mapMode.value = false
    dayRegionGrouping.value = value === 'days'
  }
})

const viewModes = computed<ViewModeOption[]>(() => {
  const modes: ViewModeOption[] = [
    { value: 'grid', label: 'Grid', disabled: false, hint: 'Every photo in one grid' },
    {
      value: 'days',
      label: 'Days',
      disabled: !dayRegionAvailable.value,
      hint: dayRegionAvailable.value
        ? 'Group by the day each photo was taken, then by place'
        : 'Pick a tag first — day sections over a whole album are as long as the album'
    }
  ]
  if (mapFilterAvailable.value) {
    modes.push({ value: 'map', label: 'Map', disabled: false, hint: 'Show located photos on a map' })
  }
  return modes
})

/**
 * Stores whatever the map is currently showing as the album's default view. Reachable only from
 * the map's own "Save this view" button, so the input is always a framing the owner is looking at.
 */
async function handleSaveMapView(view: MapView) {
  if (!album.value) return
  try {
    await saveMapView(album.value.id, view)
    success('Map view saved — the map now opens here for everyone')
  } catch (err) {
    error(err instanceof Error ? err.message : 'Could not save the map view')
  }
}

async function handleClearMapView() {
  if (!album.value) return
  try {
    await saveMapView(album.value.id, null)
    success('Map view reset — the map fits all photos again')
  } catch (err) {
    error(err instanceof Error ? err.message : 'Could not reset the map view')
  }
}

// --- Presentation groups -----------------------------------------------------------------------
const presentationSections = computed(() => buildSections(displayedFiles.value, selectedTag.value))
const lightboxGroupContext = computed(() =>
  groupContextFor(presentationSections.value, selectedFile.value?.id)
)
// Groups belong to one tag, so managing them needs a tag selected. Hidden while a slideshow is
// being recorded or played so the presentation stays chrome-free.
const canManageGroups = computed(
  () =>
    props.presentationMode &&
    isLoggedIn.value &&
    Boolean(selectedTag.value) &&
    !recording.isInRecordingMode.value &&
    !isPlaying.value
)
const groups = useGroupEditing({
  album,
  selectedTag,
  createGroup: groupsApi.createGroup,
  updateGroup: groupsApi.updateGroup,
  deleteGroup: groupsApi.deleteGroup,
  setGroupEnd: groupsApi.setGroupEnd
})

// --- Album head actions ------------------------------------------------------------------------
const upload = useUploadFlow({ album, files, reloadFiles: loader.reloadFiles })
const isDeletingAlbum = ref(false)
// A new album is created unpublished, so the share link is dead until the owner enables it.
// Treated as published when the field is missing so an older cached album never reads as a draft.
const isPublished = computed(() => album.value?.published !== false)
const togglingPublished = ref(false)

async function handleUpdateAlbumTitle(newTitle: string) {
  if (!album.value) return
  try {
    await updateAlbum(album.value.id, { name: newTitle, description: album.value.description })
  } catch (err) {
    error(`Error saving album title: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

async function handleUpdateDescription(description: string) {
  if (!album.value) return
  try {
    await updateAlbum(album.value.id, { name: album.value.name, description })
  } catch (err) {
    error(`Error saving album description: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

function togglePresentation() {
  router.push({
    name: props.presentationMode ? 'Album' : 'AlbumPresentation',
    params: { albumId: String(props.albumId) }
  })
}

async function togglePublished() {
  if (!album.value || togglingPublished.value) return
  const next = !isPublished.value
  togglingPublished.value = true
  try {
    await setPublished(album.value.id, next)
    success(
      next
        ? 'Album is public. The share link works and subscribers will be notified.'
        : 'Album is private again. The share link no longer opens and notifications stop.'
    )
  } catch {
    error('Could not change album sharing')
  } finally {
    togglingPublished.value = false
  }
}

function copyPresentationUrl() {
  if (!album.value) return
  const token = album.value.shareToken
  if (!token) {
    warning('Share token not available for this album')
    return
  }
  // Copying a link that 404s is worse than refusing to copy it: the owner would hand it out and
  // only hear about it from whoever it failed for.
  if (!isPublished.value) {
    warning('Enable public sharing for this album first (Manage → Public sharing)')
    return
  }
  const url = new URL(window.location.origin)
  url.pathname = `/public/album/${token}`
  const shareUrl = url.toString()
  if (navigator.clipboard?.writeText) {
    navigator.clipboard
      .writeText(shareUrl)
      .then(() => success('Presentation link copied to clipboard!'))
      .catch(() => window.open(shareUrl, '_blank'))
  } else {
    window.open(shareUrl, '_blank')
  }
}

async function handleReorderByFilename() {
  if (!album.value) return
  const confirmed = await confirm(
    'Reorder all files in this album by filename numbers? This will sort files based on numbers found in their filenames.',
    { type: 'warning', confirmText: 'Reorder' }
  )
  if (!confirmed) return
  try {
    const count = await reorderByFilename(album.value.id)
    await loader.reloadFiles()
    success(`Successfully reordered ${count || 'all'} files!`)
  } catch (err) {
    error(`Error reordering files: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

async function handleReorderByExif() {
  if (!album.value) return
  const confirmed = await confirm(
    'Reorder all files in this album by EXIF date? This will sort files based on the date the photo was taken (from EXIF metadata). Files without EXIF dates will be sorted by upload date.',
    { type: 'warning', confirmText: 'Reorder' }
  )
  if (!confirmed) return
  try {
    const count = await reorderByExif(album.value.id)
    await loader.reloadFiles()
    success(`Successfully reordered ${count || 'all'} files by EXIF date!`)
  } catch (err) {
    error(`Error reordering files by EXIF: ${err instanceof Error ? err.message : 'Unknown error'}`)
  }
}

async function handleDeleteAlbum() {
  if (!album.value) return
  const fileCount = files.value.length
  const confirmMessage =
    fileCount === 0
      ? `Delete "${album.value.name}"?\n\nThis album is empty and will be permanently deleted.`
      : `Delete "${album.value.name}"?\n\n⚠️ WARNING: This album contains ${fileCount} photo${fileCount !== 1 ? 's' : ''}.\nAll photos in this album will be permanently deleted!\n\nThis action cannot be undone.`

  const confirmed = await confirm(confirmMessage, { type: 'danger', confirmText: 'Delete Album' })
  if (!confirmed) return

  isDeletingAlbum.value = true
  const toastId = info(`Deleting "${album.value.name}"…`, 0)
  try {
    await deleteAlbum(album.value.id)
    removeNotification(toastId)
    router.push({ name: 'Albums' })
  } catch (err) {
    removeNotification(toastId)
    isDeletingAlbum.value = false
    error(`Error deleting album: ${err instanceof Error ? err.message : 'Unknown error'}`)
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
