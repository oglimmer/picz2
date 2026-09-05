<template>
  <div class="album-head">
    <div class="album-head-top">
      <div class="title-and-meta">
        <EditableTitle
          :title="album?.name || 'Loading…'"
          :can-edit="canEdit"
          title-tag="h1"
          @update:title="$emit('update-title', $event)"
        />
        <div class="album-meta">
          <span class="album-meta-facts">
            <strong>{{ photoCount.toLocaleString() }}</strong>&nbsp;{{ photoCount === 1 ? 'photo' : 'photos' }}<span
              class="shelf-dot"
            >·</span><strong>{{ formattedTotalSize }}</strong>
          </span>
          <router-link
            v-if="canEdit && album"
            class="album-meta-link"
            :to="{ name: 'AlbumAnalytics', params: { albumId: String(album.id) } }"
          >
            Analytics
          </router-link>
        </div>
      </div>

      <div
        v-if="canEdit"
        class="album-head-actions"
      >
        <button
          class="btn"
          @click="$emit('present')"
        >
          Present
        </button>
        <button
          class="btn"
          @click="$emit('share')"
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
              @click="close(); $emit('toggle-published')"
            >
              <span class="menu-item-label">Public sharing</span>
              <span class="menu-item-count">{{ isPublished ? 'On' : 'Off' }}</span>
            </button>
            <div class="popover-sep" />
            <button
              class="menu-item"
              :class="{ 'menu-item--on': tagPickerOpen }"
              role="menuitem"
              @click="close(); $emit('toggle-tag-picker')"
            >
              <span class="menu-item-label">Album tags</span>
              <span class="menu-item-count">{{ enabledTagCount }}</span>
            </button>
            <button
              class="menu-item"
              :class="{ 'menu-item--on': duplicateFilterActive }"
              role="menuitem"
              @click="close(); $emit('toggle-duplicates')"
            >
              <span class="menu-item-label">
                {{ duplicateFilterActive ? 'Stop checking duplicates' : 'Find duplicate names' }}
              </span>
            </button>
            <div class="popover-sep" />
            <button
              class="menu-item menu-item--danger"
              role="menuitem"
              :disabled="isDeleting"
              @click="close(); $emit('delete-album')"
            >
              <span class="menu-item-label">
                {{ isDeleting ? 'Deleting…' : 'Delete album' }}
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
          v-else-if="canEdit"
          class="add-description-btn"
          @click="startEditDescription"
        >
          + Add description
        </button>
        <button
          v-if="canEdit && album?.description"
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
</template>

<script setup lang="ts">
import { nextTick, ref } from 'vue'
import EditableTitle from './EditableTitle.vue'
import MenuButton from './MenuButton.vue'
import type { Album } from '@/types'

/**
 * The album's masthead: title, counts, description and the Manage menu. Owns only the description
 * editor's local state; everything that changes the album is emitted upwards.
 */
interface Props {
  album: Album | null
  photoCount: number
  formattedTotalSize: string
  canEdit: boolean
  isPublished: boolean
  togglingPublished: boolean
  enabledTagCount: number
  tagPickerOpen: boolean
  duplicateFilterActive: boolean
  isDeleting: boolean
}

const props = defineProps<Props>()

const emit = defineEmits<{
  present: []
  share: []
  'toggle-published': []
  'toggle-tag-picker': []
  'toggle-duplicates': []
  'delete-album': []
  'update-title': [title: string]
  'update-description': [description: string]
}>()

const isEditingDescription = ref(false)
const editedDescription = ref('')
const descriptionInput = ref<HTMLTextAreaElement | null>(null)

function startEditDescription() {
  if (!props.canEdit) return
  editedDescription.value = props.album?.description || ''
  isEditingDescription.value = true
  nextTick(() => descriptionInput.value?.focus())
}

function saveDescription() {
  emit('update-description', editedDescription.value)
  isEditingDescription.value = false
}

function cancelEditDescription() {
  isEditingDescription.value = false
  editedDescription.value = ''
}
</script>
