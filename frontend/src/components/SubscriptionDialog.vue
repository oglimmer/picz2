<template>
  <Teleport to="body">
    <Transition name="subdlg">
      <div
        v-if="show"
        class="subdlg-overlay"
        @click.self="close"
      >
        <div
          ref="panel"
          class="subdlg"
          tabindex="-1"
          role="dialog"
          aria-modal="true"
          :aria-labelledby="titleId"
          @keydown.tab="trapTab"
        >
          <button
            class="subdlg-close"
            type="button"
            aria-label="Close"
            @click="close"
          >
            <svg
              viewBox="0 0 16 16"
              aria-hidden="true"
            >
              <path
                d="M3.5 3.5l9 9m0-9l-9 9"
                stroke="currentColor"
                stroke-width="1.6"
                stroke-linecap="round"
              />
            </svg>
          </button>

          <p class="subdlg-eyebrow">
            {{ eyebrow }}
          </p>
          <h2
            :id="titleId"
            class="subdlg-title"
          >
            {{ title }}
          </h2>
          <hr class="subdlg-rule">

          <!-- Sign-up form -->
          <form
            v-if="view === 'form'"
            class="subdlg-body"
            @submit.prevent="handleSubmit"
          >
            <p class="subdlg-lede">
              New photos are gathered into one email. Every message has a one-click unsubscribe.
            </p>

            <div class="subdlg-field">
              <label
                class="subdlg-label"
                for="subscription-email"
              >Email address</label>
              <input
                id="subscription-email"
                ref="emailInput"
                v-model="formData.email"
                class="subdlg-input"
                type="email"
                autocomplete="email"
                placeholder="you@example.com"
                required
                :disabled="loading"
              >
              <p class="subdlg-hint">
                Used for these updates only.
              </p>
            </div>

            <div class="subdlg-options">
              <label
                class="subdlg-option"
                :class="{ 'is-on': formData.notifyAlbumUpdates }"
              >
                <input
                  v-model="formData.notifyAlbumUpdates"
                  class="subdlg-check"
                  type="checkbox"
                  :disabled="loading"
                >
                <span class="subdlg-option-text">
                  <span class="subdlg-option-title">New photos in this album</span>
                  <span class="subdlg-option-desc">Sent when someone adds photos or videos here.</span>
                </span>
              </label>

              <label
                class="subdlg-option"
                :class="{ 'is-on': formData.notifyNewAlbums }"
              >
                <input
                  v-model="formData.notifyNewAlbums"
                  class="subdlg-check"
                  type="checkbox"
                  :disabled="loading"
                >
                <span class="subdlg-option-text">
                  <span class="subdlg-option-title">New albums from this owner</span>
                  <span class="subdlg-option-desc">Sent when they publish another shared album.</span>
                </span>
              </label>
            </div>

            <!-- The one thing nobody can guess: push is matched to a subscription purely by
                 e-mail address. Somebody who installs the app and signs in with a different
                 address gets e-mail and silently no push, and nothing anywhere would tell them
                 why. So it is said here, next to the field it is about. -->
            <aside class="subdlg-push">
              <span
                class="subdlg-push-icon"
                aria-hidden="true"
              >📱</span>
              <span class="subdlg-push-text">
                <strong>Want these on your phone too?</strong>
                <!-- The space is explicit because Vue's default `whitespace: 'condense'` drops a
                     whitespace-only text node between two elements when it contains a newline —
                     which glued "Picz" to "on the App Store". Do not "tidy" this away. -->
                Get <em>Picz</em>{{ ' ' }}
                <a
                  v-if="appStoreUrl"
                  class="subdlg-push-link"
                  :href="appStoreUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                >on the App&nbsp;Store</a>
                <template v-else>from the App&nbsp;Store</template>
                and sign in with <strong>this same email address</strong>. Push notifications only
                reach a phone signed in with the address you enter above — anything else still gets
                the emails.
              </span>
            </aside>

            <p
              v-if="error"
              class="subdlg-error"
              role="alert"
            >
              {{ error }}
            </p>

            <div class="subdlg-actions">
              <button
                type="button"
                class="subdlg-btn subdlg-btn--quiet"
                :disabled="loading"
                @click="close"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="subdlg-btn subdlg-btn--go"
                :disabled="loading"
              >
                {{ loading ? 'Sending…' : 'Notify me' }}
              </button>
            </div>
          </form>

          <!-- Waiting on the confirmation click -->
          <div
            v-else-if="view === 'pending'"
            class="subdlg-body"
          >
            <div class="subdlg-stamp-well">
              <span class="subdlg-stamp">
                <span>Awaiting</span>
                <span>Confirmation</span>
              </span>
            </div>
            <p class="subdlg-lede subdlg-lede--center">
              We sent a link to <strong>{{ sentTo }}</strong>. Updates start the moment you click it.
            </p>
            <div class="subdlg-actions subdlg-actions--center">
              <button
                type="button"
                class="subdlg-btn subdlg-btn--go"
                @click="close"
              >
                Done
              </button>
            </div>
            <button
              type="button"
              class="subdlg-textlink"
              @click="backToForm"
            >
              Wrong address? Enter another
            </button>
          </div>

          <!-- Live subscription -->
          <div
            v-else
            class="subdlg-body"
          >
            <div class="subdlg-stamp-well">
              <span class="subdlg-stamp subdlg-stamp--sealed">
                <span>Confirmed</span>
              </span>
            </div>
            <p class="subdlg-lede subdlg-lede--center">
              We'll email <strong>{{ sentTo }}</strong> whenever {{ albumName }} changes. Every message
              has a one-click unsubscribe.
            </p>
            <div class="subdlg-actions subdlg-actions--center">
              <button
                type="button"
                class="subdlg-btn subdlg-btn--go"
                @click="close"
              >
                Done
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, reactive, computed, watch, nextTick, onUnmounted } from 'vue'
import { useApi } from '@/composables/useApi'

/**
 * Where the iOS app lives.
 *
 * Currently the App Store's iPhone apps page, not a listing for Picz — a stand-in until the
 * app is published, so the note reads as a link and lands somewhere real rather than nowhere.
 * Swap in `https://apps.apple.com/app/id…` the day the listing exists; this constant is the only
 * thing that has to change. Setting it back to '' renders the note as plain text instead.
 */
const APP_STORE_URL = 'https://apps.apple.com/de/iphone/apps'

type View = 'form' | 'pending' | 'done'

interface Props {
  show: boolean
  shareToken: string
  albumName?: string
}

const props = withDefaults(defineProps<Props>(), { albumName: 'this album' })
const emit = defineEmits<{ close: [] }>()

const { apiUrl, requestPublicJson } = useApi()
const appStoreUrl = APP_STORE_URL
const loading = ref(false)
const error = ref('')
const sentTo = ref('')
const view = ref<View>('form')
const panel = ref<HTMLElement | null>(null)
const emailInput = ref<HTMLInputElement | null>(null)
const titleId = 'subdlg-title'

const formData = reactive({
  email: '',
  notifyAlbumUpdates: true,
  notifyNewAlbums: false
})

const eyebrow = computed(() => {
  if (view.value === 'pending') return 'One step left'
  if (view.value === 'done') return 'All set'
  return 'Notify me about'
})

const title = computed(() => {
  if (view.value === 'pending') return 'Confirm in your inbox'
  if (view.value === 'done') return "You're on the list"
  return props.albumName
})

watch(() => props.show, (open) => {
  if (open) {
    view.value = 'form'
    window.addEventListener('keydown', onKeydown)
    nextTick(() => {
      if (view.value === 'form') emailInput.value?.focus()
      else panel.value?.focus?.()
    })
  } else {
    window.removeEventListener('keydown', onKeydown)
    resetForm()
  }
}, { immediate: true })

onUnmounted(() => window.removeEventListener('keydown', onKeydown))

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.stopPropagation()
    close()
  }
}

// Keep tabbing inside the dialog while it owns the screen
function trapTab(event: KeyboardEvent) {
  const focusable = panel.value?.querySelectorAll<HTMLElement>(
    'button:not([disabled]), input:not([disabled]), a[href]'
  )
  if (!focusable || focusable.length === 0) return
  const first = focusable[0]
  const last = focusable[focusable.length - 1]
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault()
    last.focus()
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault()
    first.focus()
  }
}

function resetForm() {
  formData.email = ''
  formData.notifyAlbumUpdates = true
  formData.notifyNewAlbums = false
  error.value = ''
  sentTo.value = ''
  view.value = 'form'
}

function backToForm() {
  view.value = 'form'
  error.value = ''
  nextTick(() => emailInput.value?.focus())
}

async function handleSubmit() {
  error.value = ''

  if (!formData.notifyAlbumUpdates && !formData.notifyNewAlbums) {
    error.value = 'Pick at least one thing to be notified about.'
    return
  }

  loading.value = true
  try {
    const data = await requestPublicJson<{ confirmed?: boolean }>(
      `${apiUrl}/api/public/subscriptions/albums/${props.shareToken}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: formData.email,
          notifyAlbumUpdates: formData.notifyAlbumUpdates,
          notifyNewAlbums: formData.notifyNewAlbums
        })
      }
    )
    sentTo.value = formData.email
    // An already-confirmed subscriber just changed preferences — no new email goes out
    view.value = data.confirmed ? 'done' : 'pending'
  } catch (err) {
    error.value = err instanceof Error && err.message
      ? err.message
      : 'We could not reach the server. Check your connection and try again.'
  } finally {
    loading.value = false
  }
}

function close() {
  emit('close')
}
</script>

<style scoped>
.subdlg-overlay {
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

.subdlg {
  position: relative;
  width: 100%;
  max-width: 432px;
  padding: var(--sp-8);
  background: var(--c-surface);
  border-radius: var(--r-xl);
  box-shadow: var(--sh-xl);
}

/* === HEADER LOCKUP === */

.subdlg-eyebrow {
  margin-bottom: var(--sp-1);
  padding-right: var(--sp-8);
  color: var(--c-text-3);
  font-size: .6875rem;
  font-weight: 600;
  letter-spacing: .14em;
  line-height: 1.4;
  text-transform: uppercase;
}

.subdlg-title {
  padding-right: var(--sp-8);
  color: var(--c-text);
  font-family: var(--f-display);
  font-size: 1.5rem;
  font-weight: 600;
  letter-spacing: -.01em;
  line-height: 1.25;
  overflow-wrap: anywhere;
}

.subdlg-rule {
  margin: var(--sp-5) 0;
  border: none;
  border-top: 1px solid var(--c-border);
}

.subdlg-close {
  position: absolute;
  top: var(--sp-5);
  right: var(--sp-5);
  display: flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  color: var(--c-text-3);
  background: none;
  border-radius: var(--r-sm);
  transition: color var(--t-fast), background var(--t-fast);
}
.subdlg-close svg { width: 16px; height: 16px; }
.subdlg-close:hover { color: var(--c-text); background: var(--c-surface-alt); }

/* === BODY === */

.subdlg-body {
  display: flex;
  flex-direction: column;
  gap: var(--sp-5);
}

.subdlg-lede {
  color: var(--c-text-2);
  font-size: .875rem;
  line-height: 1.6;
}
.subdlg-lede--center { text-align: center; }
.subdlg-lede strong { color: var(--c-text); font-weight: 600; }

.subdlg-field {
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}

.subdlg-label {
  color: var(--c-text-2);
  font-size: .75rem;
  font-weight: 600;
  letter-spacing: .03em;
  text-transform: uppercase;
}

.subdlg-input {
  width: 100%;
  padding: 11px var(--sp-4);
  color: var(--c-text);
  font-size: .9375rem;
  background: var(--c-surface);
  border: 1.5px solid var(--c-border);
  border-radius: var(--r-md);
  outline: none;
  transition: border-color var(--t-fast), box-shadow var(--t-fast);
}
.subdlg-input::placeholder { color: var(--c-text-3); }
.subdlg-input:focus {
  border-color: var(--c-accent);
  box-shadow: 0 0 0 3px rgba(196, 98, 45, .12);
}
.subdlg-input:disabled { opacity: .55; cursor: not-allowed; }

/* === NOTIFICATION OPTIONS === */

.subdlg-options {
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
}

.subdlg-option {
  display: flex;
  align-items: flex-start;
  gap: var(--sp-3);
  padding: var(--sp-4);
  background: var(--c-surface);
  border: 1.5px solid var(--c-border);
  border-radius: var(--r-md);
  cursor: pointer;
  transition: border-color var(--t-fast), background var(--t-fast);
}
.subdlg-option:hover { border-color: var(--c-border-2); }
.subdlg-option.is-on {
  background: var(--c-accent-soft);
  border-color: rgba(196, 98, 45, .45);
}
.subdlg-option:has(.subdlg-check:focus-visible) {
  border-color: var(--c-accent);
  box-shadow: 0 0 0 3px rgba(196, 98, 45, .12);
}

.subdlg-check {
  flex-shrink: 0;
  width: 17px;
  height: 17px;
  margin-top: 1px;
  accent-color: var(--c-accent);
  cursor: pointer;
}

.subdlg-option-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.subdlg-option-title {
  color: var(--c-text);
  font-size: .9375rem;
  font-weight: 500;
  line-height: 1.4;
}
.subdlg-option-desc {
  color: var(--c-text-2);
  font-size: .8125rem;
  line-height: 1.45;
}

/* === THE STAMP === */

.subdlg-stamp-well {
  display: flex;
  justify-content: center;
  padding: var(--sp-6) 0 var(--sp-5);
}

.subdlg-stamp {
  --stamp: var(--c-accent);
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
  padding: 13px var(--sp-6);
  color: var(--stamp);
  font-size: .8125rem;
  font-weight: 600;
  letter-spacing: .2em;
  line-height: 1.1;
  text-indent: .2em; /* balance the trailing letter-spacing */
  text-transform: uppercase;
  border: 2.5px solid var(--stamp);
  border-radius: 3px;
  opacity: .92;
  transform: rotate(-5.5deg);
  animation: subdlg-press 420ms cubic-bezier(.2, .85, .25, 1) both;
}
.subdlg-stamp::before {
  content: '';
  position: absolute;
  inset: 4px;
  border: 1px solid currentColor;
  border-radius: 1px;
  opacity: .5;
}
/* Confirmed reads as ink pressed into the paper: filled, darker edge */
.subdlg-stamp--sealed {
  --stamp: #3F5A43;
  padding: 15px var(--sp-8);
  letter-spacing: .24em;
  color: #fff;
  background: var(--c-ok);
  transform: rotate(-4deg);
}
.subdlg-stamp--sealed::before { border-color: rgba(255, 255, 255, .6); opacity: .7; }

@keyframes subdlg-press {
  0%   { opacity: 0;   transform: rotate(-13deg) scale(2.1); }
  55%  { opacity: .92; transform: rotate(-5.5deg) scale(.94); }
  78%  { transform: rotate(-5.5deg) scale(1.04); }
  100% { transform: rotate(-5.5deg) scale(1); }
}

/* === FEEDBACK & ACTIONS === */

.subdlg-error {
  padding: var(--sp-3) var(--sp-4);
  color: var(--c-danger);
  font-size: .875rem;
  font-weight: 500;
  background: var(--c-danger-soft);
  border: 1px solid rgba(184, 50, 50, .2);
  border-radius: var(--r-sm);
}

.subdlg-actions {
  display: flex;
  gap: var(--sp-3);
  justify-content: flex-end;
}
.subdlg-actions--center { justify-content: center; }

.subdlg-btn {
  padding: 10px var(--sp-6);
  font-size: .875rem;
  font-weight: 600;
  border-radius: var(--r-md);
  border: 1.5px solid transparent;
  transition: background var(--t-fast), border-color var(--t-fast), color var(--t-fast);
}
.subdlg-btn:disabled { opacity: .5; cursor: not-allowed; }

.subdlg-btn--go {
  color: #fff;
  background: var(--c-accent);
}
.subdlg-btn--go:not(:disabled):hover { background: var(--c-accent-h); }

.subdlg-btn--quiet {
  color: var(--c-text-2);
  background: var(--c-surface-alt);
  border-color: var(--c-border);
}
.subdlg-btn--quiet:not(:disabled):hover { color: var(--c-text); border-color: var(--c-text-2); }

.subdlg-textlink {
  align-self: center;
  margin-top: calc(var(--sp-2) * -1);
  color: var(--c-text-3);
  font-size: .8125rem;
  text-decoration: underline;
  text-underline-offset: 3px;
  background: none;
  transition: color var(--t-fast);
}
.subdlg-textlink:hover { color: var(--c-text-2); }

.subdlg-hint {
  color: var(--c-text-3);
  font-size: .75rem;
  line-height: 1.4;
}

/* === THE PHONE NOTE ===
   An aside, not an option: it changes nothing about the subscription, it explains why the address
   above decides whether a push can ever arrive. Tinted rather than boxed in the accent, so it
   reads as a helpful footnote and does not compete with the submit button. */
.subdlg-push {
  display: flex;
  align-items: flex-start;
  gap: var(--sp-2);
  padding: var(--sp-3);
  border: 1px solid var(--c-border);
  border-radius: 3px;
  background: var(--c-surface-alt);
}

.subdlg-push-icon {
  flex: none;
  font-size: 1rem;
  line-height: 1.45;
}

.subdlg-push-text {
  color: var(--c-text-2);
  font-size: .8125rem;
  line-height: 1.45;
}

.subdlg-push-text strong { color: var(--c-text); font-weight: 600; }
.subdlg-push-text em { font-style: normal; font-weight: 600; color: var(--c-text); }

.subdlg-push-link {
  color: var(--c-accent);
  text-decoration: underline;
  text-underline-offset: 2px;
}

.subdlg-push-link:hover { color: var(--c-accent-h); }

/* === FOCUS ===
   Inputs and option rows carry their own accent ring, so the outline goes
   to controls that have none — otherwise the email field doubles up. */

.subdlg button:focus-visible {
  outline: 2px solid var(--c-accent);
  outline-offset: 2px;
}

/* === TRANSITIONS === */

.subdlg-enter-active,
.subdlg-leave-active { transition: opacity var(--t-mid); }
.subdlg-enter-from,
.subdlg-leave-to { opacity: 0; }
.subdlg-enter-active .subdlg,
.subdlg-leave-active .subdlg { transition: transform var(--t-mid); }
.subdlg-enter-from .subdlg,
.subdlg-leave-to .subdlg { transform: scale(.96) translateY(8px); }

@media (prefers-reduced-motion: reduce) {
  .subdlg-stamp { animation: none; }
  .subdlg-enter-active,
  .subdlg-leave-active,
  .subdlg-enter-active .subdlg,
  .subdlg-leave-active .subdlg { transition: none; }
}

/* === SMALL SCREENS === */

@media (max-width: 480px) {
  .subdlg-overlay { padding: var(--sp-4); align-items: flex-start; }
  .subdlg { padding: var(--sp-6); border-radius: var(--r-lg); margin: auto 0; }
  .subdlg-title { font-size: 1.3125rem; }
  .subdlg-actions { flex-direction: column-reverse; }
  .subdlg-actions .subdlg-btn { width: 100%; }
  .subdlg-actions--center { flex-direction: column; }
}
</style>
