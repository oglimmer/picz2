<template>
  <div
    ref="root"
    class="menu-anchor"
  >
    <slot
      name="trigger"
      :open="isOpen"
      :toggle="toggle"
    >
      <button
        class="menu-trigger"
        :class="{ 'menu-trigger--on': isOpen }"
        :aria-haspopup="role"
        :aria-expanded="isOpen"
        @click="toggle"
      >
        <span
          v-if="eyebrow"
          class="menu-trigger-eyebrow"
        >{{ eyebrow }}</span>
        <span class="menu-trigger-label">{{ label }}</span>
        <svg
          class="chev"
          width="9"
          height="9"
          viewBox="0 0 10 10"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
        >
          <path d="M2 4l3 3 3-3" />
        </svg>
      </button>
    </slot>

    <Transition name="popover">
      <div
        v-if="isOpen"
        class="popover"
        :class="{ 'popover--right': align === 'right' }"
        :role="role"
      >
        <slot :close="close" />
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useMenu } from '@/composables/useMenu'

interface Props {
  label?: string
  /** Small tracked-caps label rendered inside the trigger, ahead of the value. */
  eyebrow?: string
  align?: 'left' | 'right'
  role?: 'menu' | 'listbox'
}

withDefaults(defineProps<Props>(), {
  label: '',
  eyebrow: '',
  align: 'left',
  role: 'menu'
})

const root = ref<HTMLElement | null>(null)
const { isOpen, toggle, close } = useMenu(root)

defineExpose({ close })
</script>
