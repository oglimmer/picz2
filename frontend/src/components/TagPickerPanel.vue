<template>
  <div class="tag-picker-panel">
    <div class="tag-picker-header">
      <strong>Enable tags for this album</strong>
      <span class="tag-picker-hint">
        Only enabled tags can be applied to photos or used as filters here.
      </span>
    </div>
    <div
      v-if="tags.length === 0"
      class="tag-picker-empty"
    >
      No tags defined yet. Create tags from the Albums overview first.
    </div>
    <ul
      v-else
      class="tag-picker-list"
    >
      <li
        v-for="tag in tags"
        :key="tag.id"
        class="tag-picker-item"
      >
        <label>
          <input
            type="checkbox"
            :checked="selectedTagIds.has(tag.id)"
            @change="$emit('toggle', tag.id)"
          >
          <span>{{ tag.name }}</span>
        </label>
      </li>
    </ul>
    <div class="tag-picker-actions">
      <button
        class="btn-save-small"
        :disabled="saving"
        @click="$emit('save')"
      >
        {{ saving ? 'Saving…' : 'Save' }}
      </button>
      <button
        class="btn-cancel-link"
        @click="$emit('close')"
      >
        Cancel
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { Tag } from '@/types'

/** The "Album tags" panel: tick the tags this album may use. */
defineProps<{
  tags: Tag[]
  selectedTagIds: Set<number>
  saving: boolean
}>()

defineEmits<{
  toggle: [tagId: number]
  save: []
  close: []
}>()
</script>
