<template>
  <div
    class="album-card"
    @click="$emit('click')"
  >
    <div class="album-cover">
      <img
        v-if="album.coverImageToken"
        :src="coverUrl"
        :alt="album.name"
        class="album-cover-image"
      >
      <div
        v-else
        class="album-cover-placeholder"
      >
        <span class="placeholder-icon">📁</span>
        <span class="placeholder-text">Empty Album</span>
      </div>
      <button
        v-if="canDelete"
        class="delete-album-btn-overlay"
        title="Delete album"
        @click.stop="$emit('delete', album.id)"
      >
        🗑️
      </button>
    </div>
    <div class="album-card-info">
      <h3>{{ album.name }}</h3>
      <div class="album-count">
        {{ album.fileCount }} photo{{ album.fileCount !== 1 ? 's' : '' }}
      </div>
      <div
        v-if="album.description"
        class="album-description"
      >
        {{ album.description }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useApi } from '@/composables/useApi'
import type { Album } from '@/types'

interface Props {
  album: Album
  canDelete?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  canDelete: false
})

defineEmits<{
  click: []
  delete: [albumId: number]
}>()

const { getAlbumCoverUrl } = useApi()

const coverUrl = computed(() => getAlbumCoverUrl(props.album))
</script>
