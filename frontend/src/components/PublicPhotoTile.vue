<template>
  <div
    class="gallery-item"
    @click="$emit('open', file)"
  >
    <div class="image-container">
      <LazyImage
        :src="getImageUrl(file, 'thumb')"
        :alt="file.originalName"
      />
      <div
        v-if="isVideo(file)"
        class="video-play-overlay"
      >
        <span class="play-icon">▶</span>
      </div>
    </div>
    <!-- The owner's caption (D69), read-only here. -->
    <p
      v-if="file.caption"
      class="file-caption"
      :title="file.caption"
    >
      {{ file.caption }}
    </p>
  </div>
</template>

<script setup lang="ts">
import LazyImage from './LazyImage.vue'
import { useApi } from '@/composables/useApi'
import { isVideo } from '@/utils/format'
import type { AlbumFile } from '@/types'

/** A photo on the public share page: thumbnail, video badge, caption. Nothing to edit. */
defineProps<{ file: AlbumFile }>()
defineEmits<{ open: [file: AlbumFile] }>()

const { getImageUrl } = useApi()
</script>
