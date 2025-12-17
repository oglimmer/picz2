<template>
  <div class="tag-management-panel">
    <h3>Manage Tags</h3>

    <!-- Create New Tag -->
    <div class="tag-create-section">
      <input
        v-model="newTagName"
        placeholder="New tag name"
        class="tag-input"
        maxlength="50"
        @keyup.enter="handleCreateTag"
      >
      <button
        class="btn-primary"
        @click="handleCreateTag"
      >
        Create Tag
      </button>
    </div>

    <!-- Existing Tags List -->
    <div class="tags-list">
      <div
        v-if="tags.length === 0"
        class="empty-tags"
      >
        No tags yet. Create your first tag above.
      </div>
      <div
        v-else
        class="tags-grid"
      >
        <div
          v-for="tag in tags"
          :key="tag.id"
          class="tag-item"
        >
          <div
            v-if="editingTagId !== tag.id"
            class="tag-display"
          >
            <span class="tag-name">{{ tag.name }}</span>
            <div
              v-if="tag.name !== 'no_tag'"
              class="tag-actions"
            >
              <button
                class="tag-edit-btn"
                title="Edit tag"
                @click="startEdit(tag)"
              >
                ✏️
              </button>
              <button
                class="tag-delete-btn"
                title="Delete tag"
                @click="handleDelete(tag.id)"
              >
                🗑️
              </button>
            </div>
            <span
              v-else
              class="system-tag-badge"
              title="Special system tag that cannot be modified"
            >
              (system)
            </span>
          </div>
          <div
            v-else
            class="tag-edit"
          >
            <input
              ref="tagEditInput"
              v-model="editingTagName"
              class="tag-edit-input"
              maxlength="50"
              @keyup.enter="handleSaveEdit(tag.id)"
              @keyup.esc="cancelEdit"
              @blur="handleSaveEdit(tag.id)"
            >
          </div>
        </div>
      </div>
    </div>

    <div class="form-actions">
      <button
        class="btn-secondary"
        @click="$emit('close')"
      >
        Close
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, nextTick } from 'vue'
import { useTags } from '@/composables/useTags'
import { useNotifications } from '../composables/useNotifications'
import { useConfirm } from '../composables/useConfirm'
import type { Tag } from '@/types'

interface Props {
  tags?: Tag[]
}

withDefaults(defineProps<Props>(), {
  tags: () => []
})

const emit = defineEmits<{
  close: []
  'tag-created': [tag: Tag]
  'tag-updated': [tag: Tag | undefined]
  'tag-deleted': [tagId: number]
}>()

const { createTag, updateTag, deleteTag } = useTags()
const { error, warning } = useNotifications()
const { confirm: confirmDialog } = useConfirm()

const newTagName = ref('')
const editingTagId = ref<number | null>(null)
const editingTagName = ref('')
const tagEditInput = ref<HTMLInputElement | null>(null)

async function handleCreateTag() {
  if (!newTagName.value || newTagName.value.trim() === '') {
    warning('Tag name is required')
    return
  }

  try {
    const tag = await createTag(newTagName.value)
    newTagName.value = ''
    emit('tag-created', tag)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error(`Error creating tag: ${message}`)
  }
}

function startEdit(tag: Tag) {
  editingTagId.value = tag.id
  editingTagName.value = tag.name
  nextTick(() => {
    const inputs = tagEditInput.value
    if (inputs) {
      const input = Array.isArray(inputs) ? inputs[0] : inputs
      if (input) {
        input.focus()
        input.select()
      }
    }
  })
}

async function handleSaveEdit(tagId: number) {
  if (!editingTagName.value || editingTagName.value.trim() === '') {
    cancelEdit()
    return
  }

  try {
    const tag = await updateTag(tagId, editingTagName.value)
    editingTagId.value = null
    editingTagName.value = ''
    emit('tag-updated', tag)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error(`Error updating tag: ${message}`)
  }
}

function cancelEdit() {
  editingTagId.value = null
  editingTagName.value = ''
}

async function handleDelete(tagId: number) {
  const confirmed = await confirmDialog('Delete this tag? This will remove it from all photos.', {
    type: 'danger',
    confirmText: 'Delete'
  })

  if (!confirmed) {
    return
  }

  try {
    await deleteTag(tagId)
    emit('tag-deleted', tagId)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    error(`Error deleting tag: ${message}`)
  }
}
</script>

<style scoped>
.system-tag-badge {
  color: #999;
  font-size: 0.9em;
  font-style: italic;
}
</style>
