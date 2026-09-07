<template>
  <!--
    A text card (D86): a chapter heading standing where a photo would stand.

    The background is the *next* picture in the album, blurred past recognition. That is the whole
    idea — the card belongs to what follows it, so it takes its colour from it and the shelf reads
    as one run of images rather than as a grid with a text box wedged in.
  -->
  <div class="text-card">
    <img
      v-if="backgroundUrl"
      class="text-card__bg"
      :src="backgroundUrl"
      alt=""
      aria-hidden="true"
      loading="lazy"
      decoding="async"
    >
    <span class="text-card__veil" />
    <div class="text-card__body">
      <h3 class="text-card__headline">
        {{ file.headline || file.originalName }}
      </h3>
      <p
        v-if="file.bodyText"
        class="text-card__text"
      >
        {{ file.bodyText }}
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useApi } from '@/composables/useApi'
import type { AlbumFile } from '@/types'

const props = defineProps<{
  file: AlbumFile
  /**
   * The photo the card sits in front of, or null when it is last in the album (or followed only
   * by other cards). Handed in rather than looked up here: only the list knows what comes next,
   * and it changes whenever the album is reordered.
   */
  backgroundFile?: AlbumFile | null
}>()

const { getImageUrl } = useApi()

// The thumbnail, not a bigger size: it is blurred to the point where extra pixels are invisible,
// and it is almost always already in the browser's cache from the neighbouring tile.
const backgroundUrl = computed(() =>
  props.backgroundFile ? getImageUrl(props.backgroundFile, 'thumb') : ''
)
</script>
