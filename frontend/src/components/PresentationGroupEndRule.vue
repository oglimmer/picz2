<template>
  <div class="group-end-rule">
    <span
      class="group-end-rule-tick"
      aria-hidden="true"
    />
    <span class="group-end-rule-label">End of “{{ label }}”</span>
    <span
      class="group-end-rule-line"
      aria-hidden="true"
    />
    <span
      class="group-end-rule-stop"
      aria-hidden="true"
    />
  </div>
</template>

<script setup lang="ts">
/**
 * The closing line of a group that stopped on its own end image.
 *
 * Deliberately the group header's own accent bar, laid on its side: the heading opens a section
 * with a 3px vertical rule, and this closes it with the same rule running the other way, fading
 * out into a full stop. Only drawn for a group that closed itself — a section that merely ran into
 * the next heading is already announced by that heading, and a second marker there would read as
 * two sections where there is one boundary.
 */
interface Props {
  label: string
}

defineProps<Props>()
</script>

<style scoped>
.group-end-rule {
  display: flex;
  align-items: center;
  gap: var(--sp-3);
  padding: var(--sp-4) var(--sp-8) var(--sp-2);
}

/* The heading's bar, same width and same opacity, so the eye reads the pair as one bracket. */
.group-end-rule-tick {
  flex: 0 0 3px;
  align-self: stretch;
  min-height: 14px;
  border-radius: var(--r-full);
  background: var(--c-accent);
  opacity: .75;
}

.group-end-rule-label {
  flex: 0 0 auto;
  color: var(--c-text-3);
  font-size: .6875rem;
  font-weight: 600;
  letter-spacing: .12em;
  line-height: 1.4;
  text-transform: uppercase;
  overflow-wrap: anywhere;
}

/* Thins out towards the stop rather than vanishing into it — a line that reached transparent
   before the dot left the dot floating on its own. */
.group-end-rule-line {
  flex: 1 1 auto;
  height: 2px;
  min-width: var(--sp-4);
  border-radius: var(--r-full);
  background: linear-gradient(to right, var(--c-accent), rgba(196, 98, 45, .28));
  opacity: .6;
}

/* The full stop the line trails into. Pulled back off the row gap: at the full gap it read as a
   stray dot rather than as the end of the line. */
.group-end-rule-stop {
  flex: 0 0 auto;
  width: 5px;
  height: 5px;
  margin-left: calc(4px - var(--sp-3));
  border-radius: var(--r-full);
  background: var(--c-accent);
  opacity: .55;
}

@media (max-width: 768px) {
  .group-end-rule {
    gap: var(--sp-2);
    padding: var(--sp-3) var(--sp-4) var(--sp-1);
  }
  .group-end-rule-label { letter-spacing: .08em; }
  .group-end-rule-stop { margin-left: calc(3px - var(--sp-2)); }
}
</style>
