<template>
  <Teleport to="body">
    <Transition name="txtdlg">
      <div
        v-if="show"
        class="txtdlg-overlay"
        @click.self="close"
      >
        <div
          class="txtdlg"
          role="dialog"
          aria-modal="true"
          aria-labelledby="txtdlg-title"
          @keydown.esc="close"
        >
          <p class="txtdlg-eyebrow">
            Text card
          </p>
          <h2
            id="txtdlg-title"
            class="txtdlg-title"
          >
            {{ mode === 'edit' ? 'Edit card' : 'New text card' }}
          </h2>
          <hr class="txtdlg-rule">

          <form
            class="txtdlg-body"
            @submit.prevent="handleSubmit"
          >
            <p
              v-if="mode === 'create'"
              class="txtdlg-lede"
            >
              A card holds a heading instead of a picture. It is added at the end of the album — drag it where the chapter starts, and it takes its background from the photo that follows it.
            </p>

            <div class="txtdlg-field">
              <label
                class="txtdlg-label"
                for="txtdlg-headline"
              >Headline</label>
              <input
                id="txtdlg-headline"
                ref="headlineInput"
                v-model="headline"
                class="txtdlg-input"
                type="text"
                :maxlength="MAX_HEADLINE_LENGTH"
                placeholder="e.g. Day three — over the pass"
                :disabled="saving"
                required
              >
            </div>

            <div class="txtdlg-field">
              <label
                class="txtdlg-label"
                for="txtdlg-text"
              >Text <span class="txtdlg-optional">optional</span></label>
              <textarea
                id="txtdlg-text"
                v-model="bodyText"
                class="txtdlg-input txtdlg-textarea"
                rows="4"
                :maxlength="MAX_BODY_TEXT_LENGTH"
                placeholder="A sentence or two about this part of the album."
                :disabled="saving"
              />
            </div>

            <div class="txtdlg-actions">
              <button
                type="button"
                class="txtdlg-btn txtdlg-btn-ghost"
                :disabled="saving"
                @click="close"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="txtdlg-btn txtdlg-btn-primary"
                :disabled="saving || !headline.trim()"
              >
                {{ saving ? 'Saving…' : (mode === 'edit' ? 'Save changes' : 'Add card') }}
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

/** Both mirror the server's caps in FileStorageService, so nothing is typed and then refused. */
const MAX_HEADLINE_LENGTH = 200
const MAX_BODY_TEXT_LENGTH = 4000

interface Props {
  show: boolean
  mode?: 'create' | 'edit'
  initialHeadline?: string | null
  initialBodyText?: string | null
  saving?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  mode: 'create',
  initialHeadline: '',
  initialBodyText: '',
  saving: false
})

const emit = defineEmits<{
  save: [headline: string, bodyText: string]
  close: []
}>()

const headline = ref('')
const bodyText = ref('')
const headlineInput = ref<HTMLInputElement>()

// Re-seeded on every open — one instance serves both create and edit, like the group dialog.
watch(
  () => props.show,
  async (isOpen) => {
    if (!isOpen) return
    headline.value = props.initialHeadline || ''
    bodyText.value = props.initialBodyText || ''
    await nextTick()
    headlineInput.value?.focus()
  },
  { immediate: true }
)

/** A blank body is sent as an empty string; the server stores null for it. */
function handleSubmit() {
  const trimmed = headline.value.trim()
  if (!trimmed) return
  emit('save', trimmed, bodyText.value.trim())
}

function close() {
  if (props.saving) return
  emit('close')
}
</script>

<style scoped>
.txtdlg-overlay {
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

.txtdlg {
  position: relative;
  width: 100%;
  max-width: 460px;
  padding: var(--sp-8);
  background: var(--c-surface);
  border-radius: var(--r-xl);
  box-shadow: var(--sh-xl);
}

.txtdlg-eyebrow {
  margin-bottom: var(--sp-1);
  color: var(--c-text-3);
  font-size: .6875rem;
  font-weight: 600;
  letter-spacing: .14em;
  line-height: 1.4;
  text-transform: uppercase;
}

.txtdlg-title {
  color: var(--c-text);
  font-family: var(--f-display);
  font-size: 1.5rem;
  font-weight: 600;
  letter-spacing: -.01em;
  line-height: 1.25;
}

.txtdlg-rule {
  margin: var(--sp-5) 0;
  border: none;
  border-top: 1px solid var(--c-border);
}

.txtdlg-body {
  display: flex;
  flex-direction: column;
  gap: var(--sp-5);
}

.txtdlg-lede {
  color: var(--c-text-2);
  font-size: .875rem;
  line-height: 1.6;
}

.txtdlg-field {
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}

.txtdlg-label {
  color: var(--c-text-2);
  font-size: .75rem;
  font-weight: 600;
  letter-spacing: .03em;
  text-transform: uppercase;
}
.txtdlg-optional {
  color: var(--c-text-3);
  font-weight: 500;
  letter-spacing: .02em;
  text-transform: none;
}

.txtdlg-input {
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
.txtdlg-input::placeholder { color: var(--c-text-3); }
.txtdlg-input:focus {
  border-color: var(--c-accent);
  box-shadow: 0 0 0 3px rgba(196, 98, 45, .12);
}
.txtdlg-input:disabled { opacity: .55; cursor: not-allowed; }

.txtdlg-textarea {
  resize: vertical;
  min-height: 92px;
  line-height: 1.55;
}

.txtdlg-actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--sp-3);
}

.txtdlg-btn {
  padding: 10px var(--sp-5);
  font-family: var(--f-body);
  font-size: .875rem;
  font-weight: 600;
  border-radius: var(--r-full);
  border: 1.5px solid transparent;
  cursor: pointer;
  transition: background var(--t-fast), color var(--t-fast), border-color var(--t-fast);
}
.txtdlg-btn:disabled { opacity: .55; cursor: not-allowed; }

.txtdlg-btn-ghost {
  color: var(--c-text-2);
  background: var(--c-surface);
  border-color: var(--c-border);
}
.txtdlg-btn-ghost:hover:not(:disabled) {
  color: var(--c-text);
  border-color: var(--c-border-2);
}

.txtdlg-btn-primary {
  color: #fff;
  background: var(--c-accent);
}
.txtdlg-btn-primary:hover:not(:disabled) { background: var(--c-accent-h); }

.txtdlg-enter-active, .txtdlg-leave-active { transition: opacity var(--t-mid); }
.txtdlg-enter-from, .txtdlg-leave-to { opacity: 0; }

@media (max-width: 480px) {
  .txtdlg { padding: var(--sp-6); }
  .txtdlg-actions { flex-direction: column-reverse; }
  .txtdlg-btn { width: 100%; }
}
</style>
