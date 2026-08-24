<template>
  <div
    v-if="!isEditing"
    class="title-with-edit"
  >
    <component :is="titleTag">
      {{ title }}
    </component>
    <button
      v-if="canEdit"
      class="edit-icon-btn"
      title="Edit title"
      @click="startEdit"
    >
      <svg
        width="12"
        height="12"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
      >
        <path d="M12 20h9" />
        <path d="M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4z" />
      </svg>
    </button>
  </div>
  <div
    v-else
    class="title-editor"
  >
    <input
      ref="titleInput"
      v-model="editedValue"
      class="title-input"
      @keyup.enter="save"
      @keyup.esc="cancel"
      @blur="save"
    >
  </div>
</template>

<script setup lang="ts">
import { ref, nextTick } from 'vue'

interface Props {
  title: string
  canEdit?: boolean
  titleTag?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
}

const props = withDefaults(defineProps<Props>(), {
  canEdit: false,
  titleTag: 'h1'
})

const emit = defineEmits<{
  'update:title': [value: string]
}>()

const isEditing = ref(false)
const editedValue = ref('')
const titleInput = ref<HTMLInputElement | null>(null)

function startEdit() {
  if (!props.canEdit) return
  isEditing.value = true
  editedValue.value = props.title
  nextTick(() => {
    titleInput.value?.focus()
    titleInput.value?.select()
  })
}

function save() {
  if (!editedValue.value || editedValue.value.trim() === '') {
    cancel()
    return
  }

  emit('update:title', editedValue.value)
  isEditing.value = false
}

function cancel() {
  isEditing.value = false
  editedValue.value = ''
}
</script>
