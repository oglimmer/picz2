<template>
  <div class="controls presentation-controls">
    <div
      v-if="tagsUsedInAlbum.length > 1"
      class="filter-controls"
    >
      <label for="tag-filter-presentation">Filter by tag:</label>
      <select
        id="tag-filter-presentation"
        :value="selectedTag"
        @change="$emit('update:selectedTag', ($event.target as HTMLSelectElement).value)"
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
        v-if="recordingCount > 0"
        class="audio-available-indicator"
      >AUDIO AVAILABLE</span>
    </div>
    <div
      v-if="!isRecording && !isPlaying"
      class="recording-controls"
    >
      <div
        v-if="canRecord"
        class="language-selector"
      >
        <label for="language-select">Language:</label>
        <select
          id="language-select"
          :value="selectedLanguage"
          @change="$emit('update:selectedLanguage', ($event.target as HTMLSelectElement).value as Language)"
        >
          <option value="language1">
            {{ language1Name }}
          </option>
          <option value="language2">
            {{ language2Name }}
          </option>
        </select>
      </div>
      <template
        v-for="language in LANGUAGES"
        :key="language"
      >
        <button
          v-if="hasRecordingFor(selectedTag, language)"
          class="play-btn"
          :title="`Play ${nameOf(language)} recorded slideshow`"
          @click="$emit('play', language)"
        >
          ▶️ Play {{ nameOf(language) }}
        </button>
      </template>
      <button
        v-if="canRecord && !hasRecordingFor(selectedTag, selectedLanguage)"
        class="audio-btn"
        :title="`Start audio recording slideshow in ${nameOf(selectedLanguage)}`"
        @click="$emit('record')"
      >
        🎤 Record
      </button>
      <template
        v-for="language in LANGUAGES"
        :key="`delete-${language}`"
      >
        <button
          v-if="canRecord && hasRecordingFor(selectedTag, language)"
          class="delete-recording-btn"
          :title="`Delete ${nameOf(language)} recording for ${selectedTag ? 'this filter' : 'all images'}`"
          @click="$emit('delete-recording', language)"
        >
          🗑️ Delete {{ nameOf(language) }}
        </button>
      </template>
    </div>
    <div
      v-if="isRecording"
      class="recording-status"
    >
      <span class="recording-indicator">🔴 Recording</span>
      <span>{{ recordingDuration }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { TagCount } from '@/types'
import type { Language } from '@/composables/gallery/useRecordingSession'

/** The owner's presentation toolbar: tag filter, play buttons, record and delete. */
interface Props {
  tagsUsedInAlbum: TagCount[]
  selectedTag: string
  selectedLanguage: Language
  language1Name: string
  language2Name: string
  recordingCount: number
  hasRecordings: (tag: string) => boolean
  hasRecordingFor: (tag: string, language: string) => boolean
  /** Logged in: may record and delete. */
  canRecord: boolean
  isRecording: boolean
  isPlaying: boolean
  recordingDuration: string
}

const props = defineProps<Props>()

defineEmits<{
  'update:selectedTag': [tag: string]
  'update:selectedLanguage': [language: Language]
  play: [language: Language]
  record: []
  'delete-recording': [language: Language]
}>()

const LANGUAGES: Language[] = ['language1', 'language2']

function nameOf(language: Language): string {
  return language === 'language1' ? props.language1Name : props.language2Name
}
</script>
