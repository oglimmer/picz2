<template>
  <div class="presentation-sections">
    <!-- A group that ends leaves a headingless run behind it, so there can be several of
         those in one presentation — the key carries the position for that reason. -->
    <section
      v-for="(section, sectionIndex) in sections"
      :key="section.group ? `group-${section.group.id}` : `lead-${sectionIndex}`"
      class="presentation-section"
      :class="{
        'presentation-section--lead': !section.group,
        'presentation-section--closed': section.closed
      }"
    >
      <PresentationGroupHeader
        v-if="section.group"
        :group="section.group"
        :count="section.files.length"
        :editable="editable"
        @edit="$emit('edit-group', $event)"
        @delete="$emit('delete-group', $event)"
      />
      <div class="gallery presentation-gallery">
        <template
          v-for="file in section.files"
          :key="`${file.id}:${file.publicToken}`"
        >
          <slot
            :file="file"
            :section="section"
          />
        </template>
      </div>
      <PresentationGroupEndRule
        v-if="section.closed && section.group"
        :label="section.group.label"
      />
    </section>
  </div>
</template>

<script setup lang="ts">
import PresentationGroupHeader from './PresentationGroupHeader.vue'
import PresentationGroupEndRule from './PresentationGroupEndRule.vue'
import type { AlbumFile, PresentationGroup, PresentationSection } from '@/types'

/**
 * The presentation grid split into its image groups. Headings and closing rules are drawn here;
 * the photo itself comes from the default slot, which also receives the section so the owner's
 * tile can tell whether it can end the group.
 */
interface Props {
  sections: PresentationSection[]
  /** Owner in presentation mode: show edit/remove on the group headings. */
  editable?: boolean
}

withDefaults(defineProps<Props>(), { editable: false })

defineEmits<{
  'edit-group': [group: PresentationGroup]
  'delete-group': [group: PresentationGroup]
}>()

defineSlots<{
  default(props: { file: AlbumFile; section: PresentationSection }): unknown
}>()
</script>
