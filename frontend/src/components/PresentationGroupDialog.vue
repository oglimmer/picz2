<template>
  <Teleport to="body">
    <Transition name="grpdlg">
      <div
        v-if="show"
        class="grpdlg-overlay"
        @click.self="close"
      >
        <div
          ref="panel"
          class="grpdlg"
          role="dialog"
          aria-modal="true"
          aria-labelledby="grpdlg-title"
          @keydown.esc="close"
        >
          <p class="grpdlg-eyebrow">
            {{ tag }}
          </p>
          <h2
            id="grpdlg-title"
            class="grpdlg-title"
          >
            {{ mode === 'edit' ? 'Edit group' : 'New group' }}
          </h2>
          <hr class="grpdlg-rule">

          <form
            class="grpdlg-body"
            @submit.prevent="handleSubmit"
          >
            <p
              v-if="mode === 'create'"
              class="grpdlg-lede"
            >
              The group starts at this photo and runs until the next group begins.
            </p>

            <div class="grpdlg-field">
              <label
                class="grpdlg-label"
                for="grpdlg-label-input"
              >Label</label>
              <input
                id="grpdlg-label-input"
                ref="labelInput"
                v-model="label"
                class="grpdlg-input"
                type="text"
                maxlength="120"
                placeholder="e.g. Arrival"
                :disabled="saving"
                required
              >
            </div>

            <div class="grpdlg-field">
              <label
                class="grpdlg-label"
                for="grpdlg-text-input"
              >Text <span class="grpdlg-optional">optional</span></label>
              <textarea
                id="grpdlg-text-input"
                v-model="text"
                class="grpdlg-input grpdlg-textarea"
                rows="4"
                maxlength="4000"
                placeholder="A sentence or two about this part of the album."
                :disabled="saving"
              />
            </div>

            <div class="grpdlg-actions">
              <button
                type="button"
                class="grpdlg-btn grpdlg-btn-ghost"
                :disabled="saving"
                @click="close"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="grpdlg-btn grpdlg-btn-primary"
                :disabled="saving || !label.trim()"
              >
                {{ saving ? 'Saving…' : (mode === 'edit' ? 'Save changes' : 'Create group') }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch, nextTick } from 'vue'

interface Props {
  show: boolean
  mode?: 'create' | 'edit'
  tag?: string
  initialLabel?: string
  initialText?: string | null
  saving?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  mode: 'create',
  tag: '',
  initialLabel: '',
  initialText: '',
  saving: false
})

const emit = defineEmits<{
  save: [label: string, text: string | null]
  close: []
}>()

const label = ref('')
const text = ref('')
const labelInput = ref<HTMLInputElement>()

// Reset from props every time the dialog opens — the same instance serves create and edit.
watch(
  () => props.show,
  async (isOpen) => {
    if (!isOpen) return
    label.value = props.initialLabel || ''
    text.value = props.initialText || ''
    await nextTick()
    labelInput.value?.focus()
  },
  { immediate: true }
)

function handleSubmit() {
  const trimmed = label.value.trim()
  if (!trimmed) return
  emit('save', trimmed, text.value.trim() || null)
}

function close() {
  if (props.saving) return
  emit('close')
}
</script>

<style scoped>
.grpdlg-overlay {
  position: fixed;
  inset: 0;
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--sp-6);
  overflow-y: auto;
  background: rgba(44, 26, 14, .46);
  backdrop-filter: blur(3px);
}

.grpdlg {
  position: relative;
  width: 100%;
  max-width: 460px;
  padding: var(--sp-8);
  background: var(--c-surface);
  border-radius: var(--r-xl);
  box-shadow: var(--sh-xl);
}

.grpdlg-eyebrow {
  margin-bottom: var(--sp-1);
  color: var(--c-text-3);
  font-size: .6875rem;
  font-weight: 600;
  letter-spacing: .14em;
  line-height: 1.4;
  text-transform: uppercase;
  overflow-wrap: anywhere;
}

.grpdlg-title {
  color: var(--c-text);
  font-family: var(--f-display);
  font-size: 1.5rem;
  font-weight: 600;
  letter-spacing: -.01em;
  line-height: 1.25;
}

.grpdlg-rule {
  margin: var(--sp-5) 0;
  border: none;
  border-top: 1px solid var(--c-border);
}

.grpdlg-body {
  display: flex;
  flex-direction: column;
  gap: var(--sp-5);
}

.grpdlg-lede {
  color: var(--c-text-2);
  font-size: .875rem;
  line-height: 1.6;
}

.grpdlg-field {
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}

.grpdlg-label {
  color: var(--c-text-2);
  font-size: .75rem;
  font-weight: 600;
  letter-spacing: .03em;
  text-transform: uppercase;
}
.grpdlg-optional {
  color: var(--c-text-3);
  font-weight: 500;
  letter-spacing: .02em;
  text-transform: none;
}

.grpdlg-input {
  width: 100%;
  padding: 11px var(--sp-4);
  color: var(--c-text);
  font-family: var(--f-body);
  font-size: .9375rem;
  background: var(--c-surface);
  border: 1.5px solid var(--c-border);
  border-radius: var(--r-md);
  outline: none;
  transition: border-color var(--t-fast), box-shadow var(--t-fast);
}
.grpdlg-input::placeholder { color: var(--c-text-3); }
.grpdlg-input:focus {
  border-color: var(--c-accent);
  box-shadow: 0 0 0 3px rgba(196, 98, 45, .12);
}
.grpdlg-input:disabled { opacity: .55; cursor: not-allowed; }

.grpdlg-textarea {
  resize: vertical;
  min-height: 92px;
  line-height: 1.55;
}

.grpdlg-actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--sp-3);
}

.grpdlg-btn {
  padding: 10px var(--sp-5);
  font-family: var(--f-body);
  font-size: .875rem;
  font-weight: 600;
  border-radius: var(--r-full);
  border: 1.5px solid transparent;
  cursor: pointer;
  transition: background var(--t-fast), color var(--t-fast), border-color var(--t-fast);
}
.grpdlg-btn:disabled { opacity: .55; cursor: not-allowed; }

.grpdlg-btn-ghost {
  color: var(--c-text-2);
  background: var(--c-surface);
  border-color: var(--c-border);
}
.grpdlg-btn-ghost:hover:not(:disabled) {
  color: var(--c-text);
  border-color: var(--c-border-2);
}

.grpdlg-btn-primary {
  color: #fff;
  background: var(--c-accent);
}
.grpdlg-btn-primary:hover:not(:disabled) { background: var(--c-accent-h); }

.grpdlg-enter-active, .grpdlg-leave-active { transition: opacity var(--t-mid); }
.grpdlg-enter-from, .grpdlg-leave-to { opacity: 0; }

@media (max-width: 480px) {
  .grpdlg { padding: var(--sp-6); }
  .grpdlg-actions { flex-direction: column-reverse; }
  .grpdlg-btn { width: 100%; }
}
</style>
