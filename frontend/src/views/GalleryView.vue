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

    <div
      v-if="!presentationMode"
      class="album-head"
    >
      <div class="album-head-top">
        <div class="title-and-meta">
          <EditableTitle
            :title="album?.name || 'Loading…'"
            :can-edit="isLoggedIn && !presentationMode"
            title-tag="h1"
            @update:title="handleUpdateAlbumTitle"
          />
          <div class="album-meta">
            <span class="album-meta-facts">
              <strong>{{ files.length.toLocaleString() }}</strong>&nbsp;{{ files.length === 1 ? 'photo' : 'photos' }}<span
                class="shelf-dot"
              >·</span><strong>{{ formattedTotalSize }}</strong>
            </span>
            <router-link
              v-if="isLoggedIn"
              class="album-meta-link"
              :to="{ name: 'AlbumAnalytics', params: { albumId: String(albumId) } }"
            >
              Analytics
            </router-link>
          </div>
        </div>

        <div
          v-if="isLoggedIn"
          class="album-head-actions"
        >
          <button
            class="btn"
            @click="togglePresentation"
          >
            Present
          </button>
          <button
            class="btn"
            @click="copyPresentationUrl"
          >
            Share
          </button>
          <!-- The one state an owner must not have to go looking for: whether strangers can see
               this album at all. -->
          <span
            v-if="!isPublished"
            class="album-draft-badge"
            title="Not shared yet. Manage → Public sharing turns the link on."
          >
            Private
          </span>
          <MenuButton
            label="Manage"
            align="right"
          >
            <template #default="{ close }">
              <p class="popover-head">
                This album
              </p>
              <button
                class="menu-item"
                :class="{ 'menu-item--on': isPublished }"
                role="menuitem"
                :disabled="togglingPublished"
                @click="close(); togglePublished()"
              >
                <span class="menu-item-label">Public sharing</span>
                <span class="menu-item-count">{{ isPublished ? 'On' : 'Off' }}</span>
              </button>
              <div class="popover-sep" />
              <button
                class="menu-item"
                :class="{ 'menu-item--on': tagPickerOpen }"
                role="menuitem"
                @click="close(); toggleTagPicker()"
              >
                <span class="menu-item-label">Album tags</span>
                <span class="menu-item-count">{{ enabledAlbumTags.length }}</span>
              </button>
              <button
                class="menu-item"
                :class="{ 'menu-item--on': duplicateFilterActive }"
                role="menuitem"
                @click="close(); toggleDuplicateFilter()"
              >
                <span class="menu-item-label">
                  {{ duplicateFilterActive ? 'Stop checking duplicates' : 'Find duplicate names' }}
                </span>
              </button>
              <div class="popover-sep" />
              <button
                class="menu-item menu-item--danger"
                role="menuitem"
                :disabled="isDeletingAlbum"
                @click="close(); handleDeleteAlbum()"
              >
                <span class="menu-item-label">
                  {{ isDeletingAlbum ? 'Deleting…' : 'Delete album' }}
                </span>
              </button>
            </template>
          </MenuButton>
        </div>
      </div>

      <div class="album-description-minimal">
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
            placeholder="Describe this album…"
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

    <!--
      The shelf: what the album holds, how you are looking at it, then what you can do to it.
      View mode and tag filter are separate controls — the map is a view, not a tag — and the
      rare or destructive operations sit inside named menus instead of holding permanent space.
    -->
    <div
      v-if="!presentationMode && isLoggedIn"
      class="shelf gallery-shelf"
    >
      <div class="shelf-views">
        <span class="shelf-eyebrow">View</span>
        <div class="segmented">
          <button
            v-for="mode in viewModes"
            :key="mode.value"
            class="segmented-btn"
            :class="{ 'segmented-btn--active': viewMode === mode.value }"
            :disabled="mode.disabled"
            :title="mode.hint"
            :aria-pressed="viewMode === mode.value"
            @click="viewMode = mode.value"
          >
            {{ mode.label }}
          </button>
        </div>
      </div>

      <div class="shelf-filter">
        <label
          for="tag-filter"
          class="shelf-eyebrow"
        >Tag</label>
        <select
          id="tag-filter"
          v-model="selectedTag"
          class="shelf-select"
          :disabled="viewMode === 'map'"
          :title="viewMode === 'map'
            ? 'The map shows every located photo in the album, so a tag filter does not apply'
            : 'Show only photos carrying this tag'"
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

      <div
        v-if="viewMode !== 'map'"
        class="grid-size-picker"
      >
        <button
          v-for="size in ['small', 'medium', 'large']"
          :key="size"
          class="grid-size-btn"
          :class="{ 'grid-size-btn--active': albumSize === size }"
          :title="`${size.charAt(0).toUpperCase() + size.slice(1)} thumbnails`"
          :aria-pressed="albumSize === size"
          @click="albumSize = size"
        >
          <svg
            v-if="size === 'small'"
            width="14"
            height="14"
            viewBox="0 0 14 14"
            fill="currentColor"
          >
            <rect
              x="0"
              y="0"
              width="6"
              height="6"
              rx="1"
            />
            <rect
              x="8"
              y="0"
              width="6"
              height="6"
              rx="1"
            />
            <rect
              x="0"
              y="8"
              width="6"
              height="6"
              rx="1"
            />
            <rect
              x="8"
              y="8"
              width="6"
              height="6"
              rx="1"
            />
          </svg>
          <svg
            v-else-if="size === 'medium'"
            width="14"
            height="14"
            viewBox="0 0 14 14"
            fill="currentColor"
          >
            <rect
              x="0"
              y="0"
              width="6"
              height="14"
              rx="1"
            />
            <rect
              x="8"
              y="0"
              width="6"
              height="14"
              rx="1"
            />
          </svg>
          <svg
            v-else
            width="14"
            height="14"
            viewBox="0 0 14 14"
            fill="currentColor"
          >
            <rect
              x="0"
              y="0"
              width="14"
              height="14"
              rx="1"
            />
          </svg>
        </button>
      </div>

      <span class="shelf-rule" />

      <div class="shelf-controls">
        <button
          class="action-link"
          :disabled="loadingFiles"
          @click="handleRefresh"
        >
          {{ loadingFiles ? 'Refreshing…' : 'Refresh' }}
        </button>

        <MenuButton label="Sort">
          <template #default="{ close }">
            <p class="popover-head">
              Reorder every photo by
            </p>
            <button
              class="menu-item"
              role="menuitem"
              @click="close(); handleReorderByFilename()"
            >
              <span class="menu-item-label">Number in filename</span>
            </button>
            <button
              class="menu-item"
              role="menuitem"
              @click="close(); handleReorderByExif()"
            >
              <span class="menu-item-label">Date the photo was taken</span>
            </button>
            <div class="popover-sep" />
            <button
              class="menu-item"
              :class="{ 'menu-item--on': reorderModeActive }"
              role="menuitem"
              @click="close(); toggleReorderMode()"
            >
              <span class="menu-item-label">
                {{ reorderModeActive ? 'Stop arranging by hand' : 'Arrange by hand' }}
              </span>
            </button>
          </template>
        </MenuButton>

        <MenuButton
          label="Tag all"
          align="right"
        >
          <template #default="{ close }">
            <p class="popover-head">
              Every photo in this album
            </p>
            <p
              v-if="enabledAlbumTags.length === 0"
              class="popover-note"
            >
              No tags are enabled for this album yet. Enable some under Manage → Album tags.
            </p>
            <template v-else>
              <div class="popover-field">
                <label
                  for="bulk-tag"
                  class="popover-field-label"
                >Tag</label>
                <select
                  id="bulk-tag"
                  v-model="bulkTagName"
                  class="shelf-select"
                  :disabled="!!albumTagBusy"
                >
                  <option
                    v-for="tag in enabledAlbumTags"
                    :key="tag.id"
                    :value="tag.name"
                  >
                    {{ tag.name }}
                  </option>
                </select>
              </div>
              <button
                class="menu-item"
                :disabled="albumTagDisabled"
                :title="albumTagAddTitle"
                @click="close(); handleAlbumTagAll('add')"
              >
                <span class="menu-item-label">
                  {{ albumTagBusy === 'add' ? 'Working…' : 'Add to every photo' }}
                </span>
              </button>
              <button
                class="menu-item"
                :disabled="albumTagDisabled"
                :title="albumTagRemoveTitle"
                @click="close(); handleAlbumTagAll('remove')"
              >
                <span class="menu-item-label">
                  {{ albumTagBusy === 'remove' ? 'Working…' : 'Remove from every photo' }}
                </span>
              </button>
            </template>
          </template>
        </MenuButton>

        <button
          class="new-album-btn"
          title="Upload photos to this album"
          @click="triggerFileUpload"
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
          <span>Upload photos</span>
        </button>
        <input
          ref="fileInput"
          type="file"
          multiple
          accept="image/*,video/*"
          style="display: none"
          @change="handleFileUpload"
        >
      </div>
    </div>

    <!-- A mode gets its own strip while it is on, instead of leaving its controls lying around. -->
    <div
      v-if="!presentationMode && isLoggedIn && reorderModeActive"
      class="mode-bar"
    >
      <span class="mode-bar-label">Arranging by hand</span>
      <span class="mode-bar-hint">
        {{ selectedForReorder.size > 0
          ? `${selectedForReorder.size} selected — click the gap where they should go, or move them to the top.`
          : 'Select the photos you want to move.' }}
      </span>
      <button
        class="btn"
        :disabled="selectedForReorder.size === 0"
        @click="handleMoveSelectedToTop"
      >
        Move to top
      </button>
      <button
        class="action-link"
        @click="toggleReorderMode"
      >
        Done
      </button>
    </div>

    <div
      v-if="!presentationMode && isLoggedIn && duplicateFilterActive"
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
        :disabled="selectedForDeletion.size === 0"
        @click="handleDeleteSelected"
      >
        Delete selected ({{ selectedForDeletion.size }})
      </button>
      <button
        class="action-link"
        @click="toggleDuplicateFilter"
      >
        Done
      </button>
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
          Upload photos using the macOS Share Extension
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
      v-else-if="duplicateFilterActive && displayedFiles.length === 0"
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
    <div
      v-else-if="presentationMode"
      class="presentation-sections"
    >
      <section
        v-for="section in presentationSections"
        :key="section.group ? `group-${section.group.id}` : 'lead'"
        class="presentation-section"
        :class="{ 'presentation-section--lead': !section.group }"
      >
        <PresentationGroupHeader
          v-if="section.group"
          :group="section.group"
          :count="section.files.length"
          :editable="canManageGroups"
          @edit="openEditGroupDialog"
          @delete="handleDeleteGroup"
        />
        <div class="gallery presentation-gallery">
          <GalleryItem
            v-for="file in section.files"
            :key="`${file.id}:${file.publicToken}`"
            :file="file"
            :show-file-info="false"
            :show-drag-handle="false"
            :can-start-group="canManageGroups"
            :group-start="Boolean(groupStartingAt(file.id, selectedTag))"
            @click="openLightbox"
            @start-group="openCreateGroupDialog"
          />
        </div>
      </section>
    </div>

    <!-- By day & region: one section per calendar day, one sub-section per place. The regions
         come from a complete-linkage clustering, so every photo in a region is within 2 km of
         every other one in it, not merely of its neighbour (see utils/dayRegionGrouping.ts). -->
    <div
      v-else-if="dayRegionActive"
      class="day-groups"
    >
      <section
        v-for="day in dayRegionGroups"
        :key="day.key"
        class="day-group"
      >
        <header class="day-group-header">
          <h2 class="day-group-title">
            {{ formatDayLabel(day) }}
          </h2>
          <span class="day-group-count">{{ day.count }} {{ day.count === 1 ? 'photo' : 'photos' }}</span>
        </header>

        <div
          v-for="cluster in day.clusters"
          :key="cluster.key"
          class="region-group"
        >
          <div class="region-header">
            <span class="region-name">
              <svg
                v-if="cluster.located"
                class="region-icon"
                width="11"
                height="11"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
              >
                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z" />
                <circle
                  cx="12"
                  cy="10"
                  r="3"
                />
              </svg>
              {{ regionLabel(cluster.center) }}
            </span>
            <span class="region-meta">
              {{ cluster.files.length }} {{ cluster.files.length === 1 ? 'photo' : 'photos' }}<template
                v-if="cluster.located && cluster.spreadMeters > 0"
              > · within {{ formatDistance(cluster.spreadMeters) }}</template>
            </span>
          </div>
          <div
            class="gallery"
            :class="`gallery--${albumSize}`"
          >
            <GalleryItem
              v-for="file in cluster.files"
              :key="`${file.id}:${file.publicToken}`"
              :file="file"
              :available-tags="enabledAlbumTags"
              :is-draggable="false"
              :show-drag-handle="false"
              :show-file-info="isLoggedIn"
              :selectable="isLoggedIn"
              :selected="reorderModeActive ? selectedForReorder.has(file.id) : duplicateFilterActive ? selectedForDeletion.has(file.id) : selectedFileIds.has(file.id)"
              :selection-active="selectionActive || duplicateFilterActive || reorderModeActive"
              :bulk-select="duplicateFilterActive || reorderModeActive"
              :select-variant="reorderModeActive ? 'reorder' : 'delete'"
              :move-target="reorderModeActive && selectedForReorder.size > 0 && !selectedForReorder.has(file.id)"
              @click="openLightbox"
              @delete="handleDeleteFile"
              @rotate="handleRotateImage"
              @add-tag="handleAddTag"
              @remove-tag="handleRemoveTag"
              @filter-tag="filterByTagName"
              @toggle-select="(fileId, shiftKey) => handleToggleSelect(fileId, albumIndexOf(fileId), shiftKey)"
              @move-here="handleMoveSelectedAfter"
            />
          </div>
        </div>
      </section>
    </div>

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
      :group-context="lightboxGroupContext"
      :is-recording="isInRecordingMode"
      :is-saving="savingRecording"
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
      :rotatable-count="selectedRotatableFiles.length"
      :busy="bulkActionBusy"
      :busy-label="bulkActionLabel"
      @add-tag="handleBulkAddTag"
      @rotate="handleBulkRotate"
      @delete-selected="handleBulkDelete"
      @clear="clearSelection"
    />

    <!-- Create / edit an image group -->
    <PresentationGroupDialog
      :show="groupDialogOpen"
      :mode="groupDialogMode"
      :tag="selectedTag"
      :initial-label="groupDialogTarget?.label || ''"
      :initial-text="groupDialogTarget?.text || ''"
      :saving="groupDialogSaving"
      @save="handleSaveGroup"
      @close="groupDialogOpen = false"
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
import { useUpload } from '../composables/useUpload'
import { usePresentationGroups } from '../composables/usePresentationGroups'
import { formatBytes, isVideo } from '../utils/format'
import { groupByDayAndRegion, formatDayLabel, formatDistance, DEFAULT_REGION_RADIUS_METERS } from '../utils/dayRegionGrouping'
import { useRegionNames } from '../composables/useRegionNames'
import { albumMapView } from '../types'
import GalleryItem from '../components/GalleryItem.vue'
import Lightbox from '../components/Lightbox.vue'
import EditableTitle from '../components/EditableTitle.vue'
import BulkTagBar from '../components/BulkTagBar.vue'
import PresentationGroupHeader from '../components/PresentationGroupHeader.vue'
import PresentationGroupDialog from '../components/PresentationGroupDialog.vue'
import PhotoMap from '../components/PhotoMap.vue'
import AccountMenu from '../components/AccountMenu.vue'
import MenuButton from '../components/MenuButton.vue'
import { useCapabilities } from '../composables/useCapabilities'

export default {
  name: 'GalleryView',
  components: {
    GalleryItem,
    Lightbox,
    EditableTitle,
    BulkTagBar,
    PresentationGroupHeader,
    PresentationGroupDialog,
    PhotoMap,
    AccountMenu,
    MenuButton
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
    const { isLoggedIn } = useAuth()
    const { apiUrl, fetchWithAuth } = useApi()
    const { uploadFile } = useUpload()
    const { currentAlbum, loadAlbumById, updateAlbum, saveMapView, setPublished, deleteAlbum } = useAlbums()
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
      addTagToAllFiles,
      removeTagFromAllFiles,
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
    const {
      loadGroups,
      createGroup,
      updateGroup,
      deleteGroup,
      groupStartingAt,
      buildSections,
      groupContextFor
    } = usePresentationGroups()
    const { success, error, warning, info, removeNotification } = useNotifications()
    const { confirm: confirmDialog } = useConfirm()

    const isDeletingAlbum = ref(false)
    const album = computed(() => currentAlbum.value)
    const albumMapViewValue = computed(() => albumMapView(album.value))

    /**
     * Stores whatever the map is currently showing as the album's default view. Reachable only
     * from the map's own "Save this view" button, so the input is always a framing the owner is
     * looking at right now.
     */
    async function handleSaveMapView(view) {
      if (!album.value) return
      try {
        await saveMapView(album.value.id, view)
        success('Map view saved — the map now opens here for everyone')
      } catch (err) {
        error(err.message || 'Could not save the map view')
      }
    }

    async function handleClearMapView() {
      if (!album.value) return
      try {
        await saveMapView(album.value.id, null)
        success('Map view reset — the map fits all photos again')
      } catch (err) {
        error(err.message || 'Could not reset the map view')
      }
    }
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
    const savingRecording = ref(false)
    const uploadProgress = ref({ current: 0, total: 0, status: '' })
    const isEditingDescription = ref(false)
    const editedDescription = ref('')
    const descriptionInput = ref(null)
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

    // --- Map filter -------------------------------------------------------------------
    // The map is a *view*, not a tag, but it lives in the tag dropdown because that is where
    // people already go to change what the gallery shows. It is deliberately kept out of
    // `selectedTag`: that value feeds audio recordings, presentation groups and analytics, and
    // a sentinel string leaking into any of those would be a silent data bug.
    const mapMode = ref(false)
    const mapsEnabled = ref(false)
    const { ensureLoaded: ensureCapabilities } = useCapabilities()

    ensureCapabilities()
      .then(caps => { mapsEnabled.value = Boolean(caps.maps?.enabled) })
      .catch(() => { mapsEnabled.value = false })

    // Offering the map for an album with no located photos would open an empty world map.
    const hasLocatedFiles = computed(() =>
      files.value.some(f => typeof f.gpsLatitude === 'number' && typeof f.gpsLongitude === 'number')
    )

    const mapFilterAvailable = computed(() =>
      !props.presentationMode && mapsEnabled.value && hasLocatedFiles.value
    )


    // An album can lose its located photos (last one deleted) while the map is open.
    watch(mapFilterAvailable, available => {
      if (!available) mapMode.value = false
    })

    // --- By day & region --------------------------------------------------------------------
    // A second way to read the same photos: day sections, each cut into places. Kept as its own
    // flag rather than another entry in the tag dropdown, because it is orthogonal — it re-shelves
    // whatever the tag filter already selected instead of replacing the selection.
    // Always starts off, and is deliberately not remembered across visits: the plain grid is what
    // the gallery is, and a setting from some earlier session silently re-shelving it is a worse
    // surprise than one click.
    const dayRegionGrouping = ref(false)

    // Grouping is a second reading of one filtered set, not a way to browse the whole album: day
    // sections over every photo an album holds are as long as the album and say nothing. So the
    // toggle only appears once a tag is chosen, and it groups exactly what that tag selected.
    const dayRegionAvailable = computed(
      () => !props.presentationMode && !mapMode.value && Boolean(selectedTag.value)
    )

    const dayRegionActive = computed(() => dayRegionAvailable.value && dayRegionGrouping.value)

    // Losing the tag drops grouping too, so the View control never claims a mode the page is
    // not actually in.
    watch(dayRegionAvailable, available => {
      if (!available) dayRegionGrouping.value = false
    })

    // --- View mode -------------------------------------------------------------------------
    // Grid / Days / Map used to share the tag dropdown, which meant a view was hiding in a list
    // of filters. They are now their own control, over the same two flags as before: the map is
    // still kept out of `selectedTag` (it feeds recordings, groups and analytics) and day
    // grouping still needs a tag to group.
    const viewMode = computed({
      get() {
        if (mapMode.value) return 'map'
        return dayRegionActive.value ? 'days' : 'grid'
      },
      set(value) {
        if (value === 'map') {
          mapMode.value = true
          dayRegionGrouping.value = false
          // The map is fed the whole album rather than the filtered set, so a tag left set
          // would claim to narrow something it does not. Clear it and disable the control.
          selectedTag.value = ''
          return
        }
        mapMode.value = false
        dayRegionGrouping.value = value === 'days'
      }
    })

    const viewModes = computed(() => {
      const modes = [
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

    const dayRegionGroups = computed(() =>
      dayRegionActive.value
        ? groupByDayAndRegion(displayedFiles.value, DEFAULT_REGION_RADIUS_METERS)
        : []
    )

    // Place names for the region headings, reverse-geocoded through MapKit when the server has
    // Apple Maps configured; the coordinates stand in until (or unless) a name arrives.
    const { regionLabel } = useRegionNames()

    // Shift-select ranges are indices into the full album, and the grouped view hands out files
    // in section order, so the index has to be looked up rather than read off the loop.
    const albumIndexById = computed(() => {
      const map = new Map()
      files.value.forEach((file, index) => map.set(file.id, index))
      return map
    })

    function albumIndexOf(fileId) {
      const index = albumIndexById.value.get(fileId)
      return index === undefined ? -1 : index
    }

    // Presentation image groups — sections derived from the group markers of the selected tag.
    const presentationSections = computed(() =>
      buildSections(displayedFiles.value, selectedTag.value)
    )

    // The zoomed view is where most people actually read a presentation, so the section heading
    // follows them in there. Non-presentation mode has no groups loaded, so this stays null.
    const lightboxGroupContext = computed(() =>
      groupContextFor(presentationSections.value, selectedFile.value?.id)
    )

    // Groups belong to one tag, so managing them needs a tag selected. Hidden while a
    // slideshow is being recorded or played so the presentation stays chrome-free.
    const canManageGroups = computed(() =>
      props.presentationMode &&
      isLoggedIn.value &&
      Boolean(selectedTag.value) &&
      !isInRecordingMode.value &&
      !isPlaying.value
    )

    const groupDialogOpen = ref(false)
    const groupDialogMode = ref('create')
    const groupDialogSaving = ref(false)
    const groupDialogTarget = ref(null)
    const groupDialogAnchorFileId = ref(null)

    function openCreateGroupDialog(fileId) {
      if (!selectedTag.value) {
        warning('Select a tag filter first — groups belong to one tag.')
        return
      }
      groupDialogMode.value = 'create'
      groupDialogTarget.value = null
      groupDialogAnchorFileId.value = fileId
      groupDialogOpen.value = true
    }

    function openEditGroupDialog(group) {
      groupDialogMode.value = 'edit'
      groupDialogTarget.value = group
      groupDialogAnchorFileId.value = null
      groupDialogOpen.value = true
    }

    async function handleSaveGroup(label, text) {
      if (!album.value) return

      groupDialogSaving.value = true
      try {
        if (groupDialogMode.value === 'edit') {
          await updateGroup(groupDialogTarget.value.id, { label, text })
          success('Group updated.')
        } else {
          await createGroup(
            album.value.id,
            selectedTag.value,
            groupDialogAnchorFileId.value,
            { label, text }
          )
          success('Group created.')
        }
        groupDialogOpen.value = false
      } catch (err) {
        error('Could not save group: ' + err.message)
      } finally {
        groupDialogSaving.value = false
      }
    }

    async function handleDeleteGroup(group) {
      const confirmed = await confirmDialog(
        `Remove the group "${group.label}"? The photos stay exactly where they are.`,
        { confirmText: 'Remove group', type: 'danger' }
      )
      if (!confirmed) return

      try {
        await deleteGroup(group.id)
        success('Group removed.')
      } catch (err) {
        error('Could not remove group: ' + err.message)
      }
    }

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
    // Guards the bulk bar while a rotate/delete run is in flight; the label doubles as the
    // bar's progress text.
    const bulkActionBusy = ref(false)
    const bulkActionLabel = ref('')
    const ALL_TAG = 'all'
    const SYSTEM_TAGS = new Set([ALL_TAG])
    // Which tag the album-wide Add to All / Remove from All pair acts on.
    const bulkTagName = ref('')
    // 'add' | 'remove' | null — holds the mode so the spinner lands on the button that was clicked.
    const albumTagBusy = ref(null)
    const albumTagDisabled = computed(() =>
      !!albumTagBusy.value
      || !bulkTagName.value
      || (files.value.length === 0 && !selectedTag.value)
    )
    // The bulk endpoints hit every file in the album, so the scope caption must show the
    // album-wide count even when a tag filter is narrowing the grid. With no filter the loaded set
    // *is* the album and stays live across uploads/deletes; with one, fall back to the album's own
    // fileCount (AlbumService.convertToAlbumInfo counts the whole album), which can lag a little.
    const albumFileCount = computed(() =>
      selectedTag.value
        ? (album.value?.fileCount ?? files.value.length)
        : files.value.length
    )
    // No longer rendered in the bar — a second line under the segmented control made the row's
    // baselines uneven. The count survives in the button tooltips and the confirm dialog.
    // Deliberately avoids the word "all": `all` is itself a tag name here, so "add to all" reads
    // as "add the all tag".
    const albumTagScopeText = computed(() => {
      const count = albumFileCount.value
      return `${count} photo${count !== 1 ? 's' : ''} in this album`
    })
    const albumTagAddTitle = computed(() =>
      bulkTagName.value
        ? `Add "${bulkTagName.value}" to ${albumTagScopeText.value}`
        : 'This album has no tags available yet'
    )
    const albumTagRemoveTitle = computed(() =>
      bulkTagName.value
        ? `Remove "${bulkTagName.value}" from ${albumTagScopeText.value}`
        : 'This album has no tags available yet'
    )
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

    // Keep the album-wide tag selector on a tag that still exists: the list changes when you
    // switch albums or edit it in "Manage Album Tags", and a stale name would silently 404.
    watch(enabledAlbumTags, (tags) => {
      if (!tags.some(t => t.name === bulkTagName.value)) {
        bulkTagName.value = tags.length > 0 ? tags[0].name : ''
      }
    }, { immediate: true })

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

      // Load recordings and image groups for presentation mode
      if (props.presentationMode && album.value) {
        await loadRecordings(album.value.id)
        await loadGroups(album.value.id)
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
          await loadGroups(album.value.id)
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
            await loadGroups(album.value.id)
          }
        }
      }
    })

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

    // A new album is created unpublished, so the share link is dead until the owner enables it.
    // Treated as published when the field is missing so an older cached album never reads as a
    // draft it isn't.
    const isPublished = computed(() => album.value?.published !== false)
    const togglingPublished = ref(false)

    async function togglePublished() {
      if (!album.value || togglingPublished.value) return

      const next = !isPublished.value
      togglingPublished.value = true
      try {
        await setPublished(album.value.id, next)
        success(next
          ? 'Album is public. The share link works and subscribers will be notified.'
          : 'Album is private again. The share link no longer opens and notifications stop.')
      } catch (err) {
        console.error('Error changing album sharing:', err)
        error('Could not change album sharing')
      } finally {
        togglingPublished.value = false
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

        // Copying a link that 404s is worse than refusing to copy it: the owner would hand it out
        // and only hear about it from whoever it failed for.
        if (!isPublished.value) {
          warning('Enable public sharing for this album first (Manage → Public sharing)')
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

    // Mirror the api-side state flip locally so GalleryItem's thumbnailReady computed flips to
    // false and the "Processing…" spinner replaces the thumbnail while the worker rotates.
    // awaitProcessingDone keeps it in sync afterwards (QUEUED → PROCESSING → DONE).
    async function enqueueRotate(fileId) {
      const response = await fetchWithAuth(`${apiUrl}/api/files/${fileId}/rotate`, {
        method: 'POST'
      })
      if (!response.ok) {
        throw new Error('Failed to rotate image')
      }
      const target = files.value.find(f => f.id === fileId)
      if (target) {
        target.processingStatus = 'QUEUED'
      }
    }

    /**
     * Rotate is async since Phase 4.5: api returns 202 after enqueuing a worker job. Poll
     * /api/assets/{id}/status until every id is DONE before reloading, otherwise the gallery would
     * show stale derivatives. Cap the wait so a stuck worker surfaces as a user-visible error
     * instead of an infinite spinner.
     *
     * Returns the ids the worker reported as FAILED/DEAD_LETTER, each with its message; callers
     * decide whether one failure is fatal (single image) or partial (bulk).
     */
    async function awaitProcessingDone(fileIds, timeoutMs) {
      const pending = new Set(fileIds)
      const failures = []
      const pollDeadline = Date.now() + timeoutMs
      while (pending.size > 0 && Date.now() < pollDeadline) {
        await new Promise(resolve => setTimeout(resolve, 1000))
        for (const fileId of [...pending]) {
          const statusRes = await fetchWithAuth(`${apiUrl}/api/assets/${fileId}/status`)
          if (!statusRes.ok) {
            throw new Error('Failed to read rotation status')
          }
          const status = await statusRes.json()
          const target = files.value.find(f => f.id === fileId)
          if (target && status.processingStatus) {
            target.processingStatus = status.processingStatus
          }
          if (status.processingStatus === 'DONE') {
            pending.delete(fileId)
          } else if (status.processingStatus === 'FAILED' || status.processingStatus === 'DEAD_LETTER') {
            pending.delete(fileId)
            failures.push({ fileId, message: status.error || 'Rotation failed on the worker' })
          }
        }
      }
      return failures
    }

    async function handleRotateImage(fileId) {
      try {
        info('Rotating image...')
        await enqueueRotate(fileId)

        const failures = await awaitProcessingDone([fileId], 60_000)
        if (failures.length > 0) {
          throw new Error(failures[0].message)
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
      // index < 0 means the caller could not place the file in the album (a stale grouped
      // section, say). Range-selecting from an unknown anchor would grab the wrong photos.
      if (shiftKey && lastSelectedIndex.value !== null && index >= 0) {
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

    // Videos have no rotate job, so the bulk rotate button acts on the image subset only.
    const selectedRotatableFiles = computed(() =>
      files.value.filter(f => selectedFileIds.value.has(f.id) && !isVideo(f))
    )

    async function handleBulkRotate() {
      const targets = selectedRotatableFiles.value
      if (targets.length === 0 || bulkActionBusy.value) return

      bulkActionBusy.value = true
      bulkActionLabel.value = `Rotating ${targets.length}…`
      try {
        // Enqueue everything first so the worker can chew through the jobs in parallel, then
        // wait on the whole batch — polling one image at a time would serialise the wait.
        const enqueued = []
        const failures = []
        for (const file of targets) {
          try {
            await enqueueRotate(file.id)
            enqueued.push(file.id)
          } catch (err) {
            failures.push({ fileId: file.id, message: err.message })
            console.error(`Failed to enqueue rotation for file ${file.id}:`, err)
          }
        }

        if (enqueued.length > 0) {
          // 60s each like the single-image path, but capped so a large selection can't hang the
          // bar for the rest of the session.
          const timeoutMs = Math.min(60_000 * enqueued.length, 600_000)
          failures.push(...await awaitProcessingDone(enqueued, timeoutMs))
        }

        if (album.value) {
          await loadAlbumFiles(album.value.id, props.presentationMode)
        }

        const rotated = targets.length - failures.length
        if (failures.length === 0) {
          success(`Rotated ${rotated} image${rotated !== 1 ? 's' : ''}!`)
        } else if (rotated > 0) {
          warning(`Rotated ${rotated} image${rotated !== 1 ? 's' : ''}, ${failures.length} failed.`)
        } else {
          error('Failed to rotate the selected images.')
        }
      } catch (err) {
        error(`Error rotating images: ${err.message}`)
      } finally {
        bulkActionBusy.value = false
        bulkActionLabel.value = ''
      }
    }

    async function handleBulkDelete() {
      const ids = [...selectedFileIds.value]
      if (ids.length === 0 || bulkActionBusy.value) return

      const confirmed = await confirmDialog(
        `Delete ${ids.length} selected file${ids.length !== 1 ? 's' : ''}? This action cannot be undone.`,
        { type: 'danger', confirmText: 'Delete' }
      )
      if (!confirmed) return

      bulkActionBusy.value = true
      bulkActionLabel.value = `Deleting ${ids.length}…`
      let successCount = 0
      const failedIds = []
      try {
        for (const id of ids) {
          try {
            await deleteFile(id)
            successCount++
          } catch (err) {
            failedIds.push(id)
            console.error(`Failed to delete file ${id}:`, err)
          }
        }
      } finally {
        bulkActionBusy.value = false
        bulkActionLabel.value = ''
      }

      // deleteFile splices the row out of `files`, so only the selection needs updating. Keep
      // the ids that failed selected so the user can retry them without reselecting.
      selectedFileIds.value = new Set(failedIds)
      lastSelectedIndex.value = null

      if (failedIds.length === 0) {
        success(`Successfully deleted ${successCount} file${successCount !== 1 ? 's' : ''}!`)
      } else if (successCount > 0) {
        warning(`Deleted ${successCount} file${successCount !== 1 ? 's' : ''}, ${failedIds.length} failed.`)
      } else {
        error('Failed to delete selected files.')
      }
    }

    // Album-wide add/remove of the one tag picked in the dropdown. The api's bulk endpoints are
    // per-tag, and they reject any tag outside the album's enabled list
    // (FileStorageService.addTagToAllFilesInAlbum), which is why the dropdown is fed from
    // `enabledAlbumTags` — the `all` system tag plus the album's enabled tags.
    async function handleAlbumTagAll(mode) {
      if (!album.value || albumTagBusy.value) return
      const tagName = bulkTagName.value
      if (!tagName) return
      const removing = mode === 'remove'

      // The endpoints sweep the whole album, so spell out the blast radius here — the bar itself
      // no longer shows it.
      const filterNote = selectedTag.value
        ? ` This ignores the active "${selectedTag.value}" filter.`
        : ''
      const confirmed = await confirmDialog(
        (removing
          ? `Remove "${tagName}" from ${albumTagScopeText.value}?`
          : `Add "${tagName}" to ${albumTagScopeText.value}?`) + filterNote,
        { type: 'warning', confirmText: removing ? 'Remove everywhere' : 'Add everywhere' }
      )

      if (!confirmed) {
        return
      }

      albumTagBusy.value = mode
      try {
        const count = removing
          ? await removeTagFromAllFiles(album.value.id, tagName)
          : await addTagToAllFiles(album.value.id, tagName)
        await loadAlbumFiles(album.value.id, props.presentationMode)
        if (count === 0) {
          info(removing
            ? `No photos had the "${tagName}" tag.`
            : `Every photo already has the "${tagName}" tag.`)
        } else {
          const plural = count !== 1 ? 's' : ''
          success(removing
            ? `Removed "${tagName}" from ${count} photo${plural}`
            : `Tagged ${count} photo${plural} with "${tagName}"`)
        }
      } catch (err) {
        error(`Error updating "${tagName}": ${err.message}`)
      } finally {
        albumTagBusy.value = null
      }
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
      // The save below keeps the lightbox mounted until the upload resolves, so every further
      // close gesture (backdrop click, repeated Escape) re-enters here. Swallow those instead of
      // stacking a second save, a second reload and a second toast on top of the first.
      if (savingRecording.value) return

      // If recording, stop and upload
      if (isInRecordingMode.value) {
        savingRecording.value = true
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
        } finally {
          savingRecording.value = false
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
      // TUS post-finish race: tusd 2.x sends the PATCH 204 to the client *before* invoking
      // the post-finish hook (despite the docs claiming it's synchronous). So uploadFile()
      // resolves ~200-500ms before the file_metadata row exists. Snapshot the count before
      // the upload loop and poll loadAlbumFiles after, until the row(s) show up or we hit
      // the timeout. Multipart doesn't have this race (the row is committed by the time
      // /api/upload returns 202), but the same poll-until-visible logic is harmless.
      const initialCount = files.value.length

      try {
        for (let i = 0; i < selectedFiles.length; i++) {
          const file = selectedFiles[i]
          uploadProgress.value.current = i
          uploadProgress.value.currentFileName = file.name
          uploadProgress.value.status = `Uploading ${file.name}...`

          try {
            await uploadFile(file, album.value.id, {
              onProgress: (fraction) => {
                // Sub-file progress (TUS surfaces real bytes; multipart surfaces 0/1
                // bookends). Surface as a percentage on the status line so big files
                // don't look stuck.
                const pct = Math.round(fraction * 100)
                uploadProgress.value.status = `Uploading ${file.name}... ${pct}%`
              },
            })
            successCount++
            uploadProgress.value.current = i + 1
          } catch (err) {
            errorCount++
            const message = err instanceof Error ? err.message : String(err)
            errors.push(`${file.name}: ${message}`)
            console.error(`Upload error for ${file.name}:`, err)
          }
        }

        // Show results
        uploadProgress.value.status = 'Upload complete!'

        // Reload the album files to show the new uploads. Poll for up to ~3 s since the
        // TUS post-finish hook can take 200-500ms to commit the row after PATCH 204 returns.
        const expectedCount = initialCount + successCount
        const deadline = Date.now() + 3000
        // First load happens immediately; if the row's already there (multipart, fast hook)
        // we exit on the first iteration.
        await loadAlbumFiles(album.value.id, props.presentationMode)
        while (files.value.length < expectedCount && Date.now() < deadline) {
          await new Promise((r) => setTimeout(r, 300))
          await loadAlbumFiles(album.value.id, props.presentationMode)
        }

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

    return {
      isLoggedIn,
      album,
      files,
      presentationSections,
      lightboxGroupContext,
      canManageGroups,
      groupStartingAt,
      groupDialogOpen,
      groupDialogMode,
      groupDialogSaving,
      groupDialogTarget,
      openCreateGroupDialog,
      openEditGroupDialog,
      handleSaveGroup,
      handleDeleteGroup,
      selectedFileIds,
      selectedRotatableFiles,
      bulkActionBusy,
      bulkActionLabel,
      handleBulkRotate,
      handleBulkDelete,
      selectionActive,
      frequentTags,
      handleToggleSelect,
      clearSelection,
      handleBulkAddTag,
      loadingFiles,
      formattedTotalSize,
      selectedTag,
      mapMode,
      mapFilterAvailable,
      dayRegionGrouping,
      dayRegionAvailable,
      dayRegionActive,
      dayRegionGroups,
      regionLabel,
      formatDayLabel,
      formatDistance,
      albumIndexOf,
      viewMode,
      viewModes,
      albumMapViewValue,
      handleSaveMapView,
      handleClearMapView,
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
      bulkTagName,
      albumTagBusy,
      albumTagDisabled,
      albumTagAddTitle,
      albumTagRemoveTitle,
      handleAlbumTagAll,
      selectedFile,
      draggingIndex,
      dragOverIndex,
      isInRecordingMode,
      savingRecording,
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
      handleRefresh,
      handleUpdateAlbumTitle,
      startEditDescription,
      saveDescription,
      cancelEditDescription,
      togglePresentation,
      copyPresentationUrl,
      isPublished,
      togglingPublished,
      togglePublished,
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
