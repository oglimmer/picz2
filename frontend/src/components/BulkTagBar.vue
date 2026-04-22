<template>
  <Teleport to="body">
    <Transition name="bulk-bar">
      <div
        v-if="selectedCount > 0"
        class="bulk-tag-bar"
        @keydown.esc.stop="$emit('clear')"
      >
        <span class="bulk-count">{{ selectedCount }} selected</span>

        <div
          v-if="frequentTags.length > 0"
          class="bulk-quick-tags"
        >
          <span class="bulk-label">Quick tag:</span>
          <button
            v-for="tag in frequentTags"
            :key="tag.name"
            class="bulk-quick-btn"
            :title="`Tag all selected with &quot;${tag.name}&quot;`"
            @click="$emit('add-tag', tag.name)"
          >
            {{ tag.name }}
          </button>
        </div>

        <div class="bulk-custom-tag">
          <input
            ref="tagInput"
            v-model="customTag"
            class="bulk-tag-input"
            placeholder="Type or pick a tag…"
            list="bulk-tag-list"
            @keydown.enter.prevent="applyCustomTag"
            @keydown.esc.stop="clearCustomTag"
          >
          <datalist id="bulk-tag-list">
            <option
              v-for="tag in availableTags"
              :key="tag.id"
              :value="tag.name"
            />
          </datalist>
          <button
            class="bulk-apply-btn"
            :disabled="!customTag.trim()"
            @click="applyCustomTag"
          >
            Apply
          </button>
        </div>

        <button
          class="bulk-clear-btn"
          title="Clear selection (Esc)"
          @click="$emit('clear')"
        >
          ✕ Clear
        </button>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import type { Tag, TagCount } from '@/types'

const props = defineProps<{
  selectedCount: number
  availableTags: Tag[]
  frequentTags: TagCount[]
}>()

const emit = defineEmits<{
  'add-tag': [tagName: string]
  clear: []
}>()

const customTag = ref('')
const tagInput = ref<HTMLInputElement | null>(null)

function applyCustomTag() {
  const name = customTag.value.trim()
  if (name) {
    emit('add-tag', name)
    customTag.value = ''
  }
}

function clearCustomTag() {
  customTag.value = ''
}

defineExpose({ tagInput })
</script>
