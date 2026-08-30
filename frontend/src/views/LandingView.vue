<template>
  <div class="landing">
    <nav class="lp-nav">
      <span class="lp-brand">Picz</span>
      <div class="lp-nav-links">
        <router-link to="/privacy">
          Privacy
        </router-link>
        <router-link to="/imprint">
          Imprint
        </router-link>
        <button
          class="lp-btn lp-btn--ghost"
          @click="goToLogin"
        >
          Sign in
        </button>
      </div>
    </nav>

    <header class="lp-hero">
      <div class="lp-hero-text">
        <p class="lp-eyebrow">
          Private galleries, narrated
        </p>
        <h1 class="lp-headline">
          Your trip,<br>told out loud.
        </h1>
        <p class="lp-lede">
          Upload the photos, talk over them once, and send one link.
          Whoever opens it just watches — your voice, your order, your photos.
        </p>
        <div class="lp-hero-actions">
          <button
            class="lp-btn lp-btn--solid"
            @click="goToLogin"
          >
            Start a gallery
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              aria-hidden="true"
            >
              <line
                x1="5"
                y1="12"
                x2="19"
                y2="12"
              /><polyline points="12 5 19 12 12 19" />
            </svg>
          </button>
          <span class="lp-hero-note">Viewers never need an account.</span>
        </div>
      </div>

      <figure class="lp-plate">
        <div class="lp-plate-mat">
          <transition
            name="lp-x"
            mode="out-in"
          >
            <CyanotypeScene
              :key="active.scene"
              :name="active.scene"
              :label="`${active.place}, day ${active.day}`"
            />
          </transition>
        </div>
        <figcaption class="lp-plate-caption">
          <span class="lp-plate-line">“{{ active.line }}”</span>
          <span class="lp-plate-meta">
            {{ String(activeIndex + 1).padStart(2, '0') }} / {{ String(STOPS.length).padStart(2, '0') }}
            <i>·</i> {{ active.coords }}
          </span>
        </figcaption>
      </figure>
    </header>

    <!-- The tape: one recording, and the photos it turns. -->
    <section
      class="lp-tape"
      aria-label="Sample narrated gallery"
    >
      <div class="lp-tape-head">
        <button
          class="lp-transport"
          :aria-label="playing ? 'Pause the sample' : 'Play the sample'"
          @click="toggle"
        >
          <svg
            width="14"
            height="16"
            viewBox="0 0 14 16"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              v-if="playing"
              d="M1 1h4v14H1zM9 1h4v14H9z"
            />
            <path
              v-else
              d="M2 1l11 7-11 7z"
            />
          </svg>
        </button>
        <span class="lp-clock">{{ clock }} <i>/</i> {{ totalClock }}</span>
        <span class="lp-nowplaying">Day {{ active.day }} · {{ active.place }}</span>
        <span class="lp-tape-tag">Sample gallery</span>
      </div>

      <div
        class="lp-wave"
        aria-hidden="true"
      >
        <span
          v-for="(h, i) in bars"
          :key="i"
          class="lp-wave-bar"
          :class="{ 'is-past': i / bars.length <= progress }"
          :style="{ height: `${Math.round(h * 100)}%` }"
        />
        <span
          class="lp-playhead"
          :style="{ left: `${progress * 100}%` }"
        />
      </div>

      <ol class="lp-rail">
        <li
          v-for="(stop, i) in STOPS"
          :key="stop.at"
        >
          <button
            class="lp-frame"
            :class="{ 'is-active': i === activeIndex }"
            :aria-current="i === activeIndex ? 'true' : undefined"
            @click="seekTo(i)"
          >
            <CyanotypeScene
              :name="stop.scene"
              :label="`${stop.place}, day ${stop.day}`"
            />
            <span class="lp-frame-time">{{ format(stop.at) }}</span>
          </button>
        </li>
      </ol>
    </section>

    <section class="lp-spine">
      <h2 class="lp-h2">
        Three things, in order.
      </h2>
      <div class="lp-spine-grid">
        <article
          v-for="step in SPINE"
          :key="step.label"
          class="lp-step"
        >
          <p class="lp-step-label">
            {{ step.label }}
          </p>
          <h3 class="lp-step-title">
            {{ step.title }}
          </h3>
          <p class="lp-step-body">
            {{ step.body }}
          </p>
        </article>
      </div>
    </section>

    <section class="lp-more">
      <h2 class="lp-h2">
        Also inside.
      </h2>
      <dl class="lp-rows">
        <div
          v-for="row in MORE"
          :key="row.label"
          class="lp-row"
        >
          <dt>{{ row.label }}</dt>
          <dd>{{ row.body }}</dd>
        </div>
      </dl>
    </section>

    <section class="lp-creed">
      <p class="lp-creed-line">
        No feed.<br>No algorithm.<br>No ads.<br>No lock-in.
      </p>
      <div class="lp-creed-side">
        <p>
          Picz shows your photos to the people you send the link to, in the order you chose,
          and stops there. Nothing is recommended, ranked, or shown to anyone else.
        </p>
        <p>
          And the files can stay on storage you own. Connect your own S3 bucket, put an album on it,
          and Picz keeps only the gallery around your photos.
        </p>
        <button
          class="lp-btn lp-btn--solid"
          @click="goToLogin"
        >
          Start a gallery
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <line
              x1="5"
              y1="12"
              x2="19"
              y2="12"
            /><polyline points="12 5 19 12 12 19" />
          </svg>
        </button>
      </div>
    </section>

    <footer class="lp-footer">
      <span class="lp-footer-copy">© {{ new Date().getFullYear() }} Picz</span>
      <div class="lp-footer-links">
        <router-link to="/privacy">
          Privacy
        </router-link>
        <router-link to="/terms">
          Terms
        </router-link>
        <router-link to="/imprint">
          Imprint
        </router-link>
      </div>
      <span class="lp-footer-build">
        Frontend v{{ frontendVersion }} · Backend v{{ backendVersion }}
      </span>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import CyanotypeScene from '@/components/CyanotypeScene.vue';
import { useVersion } from '@/composables/useVersion';

const router = useRouter();
const { frontendVersion, backendVersion } = useVersion();

function goToLogin() {
  router.push('/login');
}

/* ---------------------------------------------------------------------------
 * The sample gallery. Eight stops on one recording — the same shape a real
 * `PlaybackTimelineEntry` has: a point in the audio, and the photo that was on
 * screen at that point.
 * ------------------------------------------------------------------------- */

interface Stop {
  /** Seconds into the recording. */
  at: number;
  day: string;
  place: string;
  coords: string;
  scene: string;
  line: string;
}

const STOPS: Stop[] = [
  { at: 0,   day: '1', place: 'Lisbon, PT',       coords: '38.7075° N, 9.1364° W', scene: 'harbour', line: 'Landed at four. Walked straight down to the water.' },
  { at: 52,  day: '1', place: 'Alfama, PT',       coords: '38.7139° N, 9.1300° W', scene: 'azulejo', line: 'Every second wall is tiled. I photographed a wall.' },
  { at: 98,  day: '2', place: 'Bairro Alto, PT',  coords: '38.7130° N, 9.1450° W', scene: 'tram',    line: 'The 28 is not a tram. The 28 is a fairground ride.' },
  { at: 134, day: '3', place: 'Sintra, PT',       coords: '38.7876° N, 9.3904° W', scene: 'palace',  line: 'Fog until eleven, and then the towers came out of it.' },
  { at: 185, day: '4', place: 'Cabo da Roca, PT', coords: '38.7803° N, 9.4989° W', scene: 'cliffs',  line: 'The westmost point of Europe. Hold on to your hat.' },
  { at: 238, day: '5', place: 'Cascais, PT',      coords: '38.6968° N, 9.4215° W', scene: 'market',  line: 'Bought figs at the market. Ate all of the figs.' },
  { at: 287, day: '5', place: 'Cascais, PT',      coords: '38.6970° N, 9.4220° W', scene: 'terrace', line: 'Dinner ran on until they switched the lamps on.' },
  { at: 341, day: '6', place: 'Lisbon, PT',       coords: '38.7169° N, 9.1399° W', scene: 'night',   line: 'Last night. Rooftops, one moon, nobody wanted to go in.' },
];

/** Length of the sample recording, in seconds. */
const TOTAL = 400;
/** How long one pass takes on screen. The sample plays faster than it was recorded. */
const LOOP_SECONDS = 48;

const SPINE = [
  {
    label: 'Upload',
    title: 'Drop in the whole camera roll.',
    body: 'Picz files each photo under the day it was taken, and inside that day under the place it was taken. Nothing to name, nothing to drag into order.',
  },
  {
    label: 'Narrate',
    title: 'Press record and talk.',
    body: 'Your voice is saved against whichever photo was on screen when you said it. Play the recording back and the photos turn themselves.',
  },
  {
    label: 'Share',
    title: 'Send one link.',
    body: 'Whoever opens it watches the gallery as you left it. No account to make, no app to install, nothing to download.',
  },
];

const MORE = [
  { label: 'Tags', body: 'Tag a photo once, then pull up every photo that matches it.' },
  { label: 'Map', body: 'Every located photo of the trip, on one map.' },
  { label: 'Groups', body: 'Put several albums together and present them as a single show.' },
  { label: 'Slideshow', body: 'Full-screen playback, with the narration or without it.' },
  { label: 'Video', body: 'Videos upload and play in line with the photos.' },
  { label: 'Your own storage', body: 'Point an album at your own S3 bucket — AWS, Cloudflare R2, Backblaze, Hetzner and more. The gallery stays here, the files stay yours, and nothing you keep there counts against your space.' },
];

/* --- waveform ------------------------------------------------------------ */

/** Small seeded PRNG, so the waveform is the same shape on every visit. */
function mulberry32(seed: number) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const BAR_COUNT = 132;
const bars: number[] = (() => {
  const rnd = mulberry32(0x28_04_24);
  return Array.from({ length: BAR_COUNT }, (_, i) => {
    const at = (i / BAR_COUNT) * TOTAL;
    // Someone taking a breath before the next photo: quiet either side of a change.
    const nearest = Math.min(...STOPS.map((s) => Math.abs(s.at - at)));
    const breath = Math.min(1, 0.05 + Math.pow(nearest / 9, 1.3));
    // Long swells for phrases, the random term for syllables inside them.
    const phrase = 0.22 + 0.78 * Math.pow(Math.abs(Math.sin(i / 16.5 + 1.1)), 0.9);
    const syllable = 0.28 + 0.72 * rnd();
    return Math.max(0.05, Math.min(1, breath * phrase * syllable * 1.45));
  });
})();

/* --- transport ----------------------------------------------------------- */

const elapsed = ref(0);
const playing = ref(false);
let raf = 0;
let lastFrame = 0;

const progress = computed(() => elapsed.value / TOTAL);
const activeIndex = computed(() => {
  let i = 0;
  for (let n = 0; n < STOPS.length; n += 1) if (STOPS[n].at <= elapsed.value) i = n;
  return i;
});
const active = computed(() => STOPS[activeIndex.value]);

function format(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}
const clock = computed(() => format(elapsed.value));
const totalClock = format(TOTAL);

function tick(now: number) {
  if (!playing.value) return;
  const delta = lastFrame ? (now - lastFrame) / 1000 : 0;
  lastFrame = now;
  elapsed.value = (elapsed.value + (delta * TOTAL) / LOOP_SECONDS) % TOTAL;
  raf = requestAnimationFrame(tick);
}

function play() {
  if (playing.value) return;
  playing.value = true;
  lastFrame = 0;
  raf = requestAnimationFrame(tick);
}

function pause() {
  playing.value = false;
  cancelAnimationFrame(raf);
}

function toggle() {
  if (playing.value) pause();
  else play();
}

function seekTo(index: number) {
  elapsed.value = STOPS[index].at;
  lastFrame = 0;
}

onMounted(() => {
  document.body.classList.add('landing-page', 'landing-dark');
  const still = window.matchMedia('(prefers-reduced-motion: reduce)');
  if (!still.matches) play();
});

onBeforeUnmount(() => {
  pause();
  document.body.classList.remove('landing-page', 'landing-dark');
});
</script>
