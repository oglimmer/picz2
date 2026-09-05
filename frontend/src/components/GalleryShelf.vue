<template>
  <!--
    The shelf: what the album holds, how you are looking at it, then what you can do to it.
    View mode and tag filter are separate controls — the map is a view, not a tag — and the
    rare or destructive operations sit inside named menus instead of holding permanent space.
  -->
  <div class="shelf gallery-shelf">
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
          @click="$emit('update:viewMode', mode.value)"
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
        class="shelf-select"
        :value="selectedTag"
        :disabled="viewMode === 'map'"
        :title="viewMode === 'map'
          ? 'The map shows every located photo in the album, so a tag filter does not apply'
          : 'Show only photos carrying this tag'"
        @change="$emit('update:selectedTag', ($event.target as HTMLSelectElement).value)"
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

    <GridSizePicker
      v-if="viewMode !== 'map'"
      :model-value="gridSize"
      @update:model-value="$emit('update:gridSize', $event)"
    />

    <span class="shelf-rule" />

    <div class="shelf-controls">
      <button
        class="action-link"
        :disabled="loading"
        @click="$emit('refresh')"
      >
        {{ loading ? 'Refreshing…' : 'Refresh' }}
      </button>

      <MenuButton label="Sort">
        <template #default="{ close }">
          <p class="popover-head">
            Reorder every photo by
          </p>
          <button
            class="menu-item"
            role="menuitem"
            @click="close(); $emit('reorder-by-filename')"
          >
            <span class="menu-item-label">Number in filename</span>
          </button>
          <button
            class="menu-item"
            role="menuitem"
            @click="close(); $emit('reorder-by-exif')"
          >
            <span class="menu-item-label">Date the photo was taken</span>
          </button>
          <div class="popover-sep" />
          <button
            class="menu-item"
            :class="{ 'menu-item--on': reorderModeActive }"
            role="menuitem"
            @click="close(); $emit('toggle-reorder')"
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
                class="shelf-select"
                :value="albumTagName"
                :disabled="!!albumTagBusy"
                @change="$emit('update:albumTagName', ($event.target as HTMLSelectElement).value)"
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
              @click="close(); $emit('tag-all', 'add')"
            >
              <span class="menu-item-label">
                {{ albumTagBusy === 'add' ? 'Working…' : 'Add to every photo' }}
              </span>
            </button>
            <button
              class="menu-item"
              :disabled="albumTagDisabled"
              :title="albumTagRemoveTitle"
              @click="close(); $emit('tag-all', 'remove')"
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
        @click="fileInput?.click()"
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
        @change="onFilesPicked"
      >
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import GridSizePicker, { type GridSize } from './GridSizePicker.vue'
import MenuButton from './MenuButton.vue'
import type { Tag } from '@/types'
import type { AlbumTagMode } from '@/composables/gallery/useAlbumTagAll'

export type ViewMode = 'grid' | 'days' | 'map'

export interface ViewModeOption {
  value: ViewMode
  label: string
  disabled: boolean
  hint: string
}

interface Props {
  viewMode: ViewMode
  viewModes: ViewModeOption[]
  selectedTag: string
  enabledAlbumTags: Tag[]
  gridSize: GridSize
  loading: boolean
  reorderModeActive: boolean
  albumTagName: string
  albumTagBusy: AlbumTagMode | null
  albumTagDisabled: boolean
  albumTagAddTitle: string
  albumTagRemoveTitle: string
}

defineProps<Props>()

const emit = defineEmits<{
  'update:viewMode': [mode: ViewMode]
  'update:selectedTag': [tag: string]
  'update:gridSize': [size: GridSize]
  'update:albumTagName': [tag: string]
  refresh: []
  'reorder-by-filename': []
  'reorder-by-exif': []
  'toggle-reorder': []
  'tag-all': [mode: AlbumTagMode]
  'files-picked': [files: File[]]
}>()

const fileInput = ref<HTMLInputElement | null>(null)

function onFilesPicked(event: Event) {
  const input = event.target as HTMLInputElement
  const files = Array.from(input.files || [])
  // Reset so the same files can be picked again later.
  input.value = ''
  if (files.length > 0) emit('files-picked', files)
}
</script>
