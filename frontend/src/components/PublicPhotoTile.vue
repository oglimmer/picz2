<template>
  <div
    class="gallery-item"
    @click="$emit('open', file)"
  >
    <div class="image-container">
      <!-- D86: a text card carries a chapter heading instead of pixels. Read-only here, like
           everything else on a share page. -->
      <TextCardTile
        v-if="isCard"
        :file="file"
        :background-file="backgroundFile"
      />
      <template v-else>
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
      </template>
    </div>
    <!-- The owner's caption (D69), read-only here. A card's words are inside the tile. -->
    <p
      v-if="file.caption && !isCard"
      class="file-caption"
      :title="file.caption"
    >
      {{ file.caption }}
    </p>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import LazyImage from './LazyImage.vue'
import TextCardTile from './TextCardTile.vue'
import { useApi } from '@/composables/useApi'
import { isTextCard, isVideo } from '@/utils/format'
import type { AlbumFile } from '@/types'

/** A photo on the public share page: thumbnail, video badge, caption. Nothing to edit. */
const props = defineProps<{
  file: AlbumFile
  /** For a text card: the photo it borrows its blurred background from, or null. */
  backgroundFile?: AlbumFile | null
}>()

// A card opens full screen like a photo (D86): the lightbox draws it as a chapter page, so the
// visitor reading the album zoomed in meets its headings where they belong.
defineEmits<{ open: [file: AlbumFile] }>()

const { getImageUrl } = useApi()

const isCard = computed(() => isTextCard(props.file))
</script>
