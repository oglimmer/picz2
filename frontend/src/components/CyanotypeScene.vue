<template>
  <svg
    class="cs"
    viewBox="0 0 400 300"
    preserveAspectRatio="xMidYMid slice"
    role="img"
    :aria-label="label"
  >
    <defs>
      <linearGradient
        :id="skyId"
        x1="0"
        y1="0"
        x2="0"
        y2="1"
      >
        <stop
          offset="0%"
          :stop-color="sky[0]"
        />
        <stop
          offset="100%"
          :stop-color="sky[1]"
        />
      </linearGradient>
      <radialGradient
        :id="glowId"
        cx="50%"
        cy="50%"
        r="50%"
      >
        <stop
          offset="0%"
          stop-color="#E9944F"
          stop-opacity=".85"
        />
        <stop
          offset="100%"
          stop-color="#E9944F"
          stop-opacity="0"
        />
      </radialGradient>
      <pattern
        v-if="name === 'azulejo'"
        :id="tileId"
        width="50"
        height="50"
        patternUnits="userSpaceOnUse"
      >
        <rect
          width="50"
          height="50"
          fill="#173B58"
        />
        <path
          d="M25 6 44 25 25 44 6 25Z"
          fill="none"
          stroke="#9CC3DC"
          stroke-width="2"
        />
        <circle
          cx="25"
          cy="25"
          r="5"
          fill="#9CC3DC"
          opacity=".55"
        />
        <circle
          cx="0"
          cy="0"
          r="3"
          fill="#9CC3DC"
          opacity=".4"
        />
        <circle
          cx="50"
          cy="0"
          r="3"
          fill="#9CC3DC"
          opacity=".4"
        />
        <circle
          cx="0"
          cy="50"
          r="3"
          fill="#9CC3DC"
          opacity=".4"
        />
        <circle
          cx="50"
          cy="50"
          r="3"
          fill="#9CC3DC"
          opacity=".4"
        />
      </pattern>
    </defs>

    <rect
      width="400"
      height="300"
      :fill="`url(#${skyId})`"
    />

    <!-- Day 1 — the water at the end of the walk -->
    <g v-if="name === 'harbour'">
      <circle
        cx="298"
        cy="150"
        r="70"
        :fill="`url(#${glowId})`"
      />
      <circle
        cx="298"
        cy="150"
        r="24"
        fill="#F0B071"
      />
      <rect
        y="172"
        width="400"
        height="128"
        fill="#0A1C2E"
      />
      <g
        fill="#E9944F"
        opacity=".45"
      >
        <rect
          x="286"
          y="182"
          width="24"
          height="4"
          rx="2"
        />
        <rect
          x="278"
          y="198"
          width="40"
          height="4"
          rx="2"
        />
        <rect
          x="288"
          y="216"
          width="20"
          height="3"
          rx="1.5"
        />
        <rect
          x="272"
          y="236"
          width="52"
          height="3"
          rx="1.5"
        />
      </g>
      <line
        x1="0"
        y1="172"
        x2="400"
        y2="172"
        stroke="#9CC3DC"
        stroke-width="1.5"
        opacity=".6"
      />
      <g fill="#061520">
        <path d="M74 172h84l-14 22H88Z" />
        <rect
          x="112"
          y="118"
          width="3"
          height="54"
        />
        <path d="M118 126h34l-34 32Z" />
      </g>
      <g
        stroke="#9CC3DC"
        stroke-width="1.5"
        opacity=".3"
        fill="none"
      >
        <path d="M20 214q18-8 36 0t36 0" />
        <path d="M40 246q22-9 44 0t44 0" />
      </g>
    </g>

    <!-- Day 1 — Alfama, where every wall is tiled -->
    <g v-else-if="name === 'azulejo'">
      <rect
        width="400"
        height="300"
        :fill="`url(#${tileId})`"
      />
      <circle
        cx="352"
        cy="44"
        r="80"
        :fill="`url(#${glowId})`"
      />
      <rect
        y="252"
        width="400"
        height="48"
        fill="#0A1C2E"
      />
      <rect
        y="248"
        width="400"
        height="5"
        fill="#9CC3DC"
        opacity=".5"
      />
    </g>

    <!-- Day 2 — the 28 climbing Bairro Alto -->
    <g v-else-if="name === 'tram'">
      <circle
        cx="200"
        cy="200"
        r="140"
        :fill="`url(#${glowId})`"
        opacity=".5"
      />
      <path
        d="M0 300V88h86v212Z"
        fill="#0A2032"
      />
      <path
        d="M400 300V62h-78v238Z"
        fill="#0A2032"
      />
      <g
        fill="#F0B071"
        opacity=".7"
      >
        <rect
          x="16"
          y="112"
          width="16"
          height="22"
        />
        <rect
          x="52"
          y="168"
          width="16"
          height="22"
        />
        <rect
          x="336"
          y="92"
          width="16"
          height="22"
        />
        <rect
          x="336"
          y="152"
          width="16"
          height="22"
        />
      </g>
      <g
        stroke="#9CC3DC"
        stroke-width="1.5"
        opacity=".4"
      >
        <line
          x1="0"
          y1="46"
          x2="400"
          y2="60"
        />
        <line
          x1="0"
          y1="70"
          x2="400"
          y2="84"
        />
      </g>
      <path
        d="M104 300l30-52h132l30 52Z"
        fill="#0C2740"
      />
      <rect
        x="132"
        y="104"
        width="136"
        height="28"
        rx="7"
        fill="#071A28"
      />
      <rect
        x="118"
        y="128"
        width="164"
        height="132"
        rx="12"
        fill="#071A28"
      />
      <g fill="#F5C089">
        <rect
          x="134"
          y="150"
          width="40"
          height="44"
          rx="4"
        />
        <rect
          x="180"
          y="150"
          width="40"
          height="44"
          rx="4"
        />
        <rect
          x="226"
          y="150"
          width="40"
          height="44"
          rx="4"
        />
      </g>
      <rect
        x="118"
        y="208"
        width="164"
        height="6"
        fill="#E9944F"
      />
      <circle
        cx="200"
        cy="240"
        r="28"
        :fill="`url(#${glowId})`"
      />
      <circle
        cx="200"
        cy="240"
        r="12"
        fill="#F5C089"
      />
    </g>

    <!-- Day 4 — the end of Europe, very windy -->
    <g v-else-if="name === 'cliffs'">
      <circle
        cx="220"
        cy="128"
        r="120"
        :fill="`url(#${glowId})`"
        opacity=".4"
      />
      <rect
        y="158"
        width="400"
        height="142"
        fill="#16456A"
      />
      <line
        x1="0"
        y1="158"
        x2="400"
        y2="158"
        stroke="#DCEDF6"
        stroke-width="2"
        opacity=".85"
      />
      <g
        stroke="#DCEDF6"
        stroke-width="1.5"
        fill="none"
        opacity=".22"
      >
        <path d="M180 196q42-10 84 0t84 0" />
        <path d="M210 226q46-11 92 0t92 0" />
      </g>
      <path
        d="M0 300V110l34-26 36 20 26-12 24 32 18 66 12 110Z"
        fill="#061520"
      />
      <path
        d="M120 190l18 66 12 44H92Z"
        fill="#0C2B3E"
      />
      <path
        d="M246 300l16-134 14 24 12-38 18 50 14 98Z"
        fill="#071E2C"
      />
      <path
        d="M288 152l18 50 14 98h-22Z"
        fill="#0C2B3E"
      />
      <g
        stroke="#EAF4FA"
        stroke-width="3.5"
        fill="none"
        opacity=".7"
        stroke-linecap="round"
      >
        <path d="M142 262q24 14 50 4" />
        <path d="M226 286q26 13 54 2" />
        <path d="M326 268q22 12 46 2" />
      </g>
      <g
        stroke="#EAF4FA"
        stroke-width="2.5"
        fill="none"
        opacity=".85"
      >
        <path d="M186 52q9-8 17 0" />
        <path d="M214 36q8-7 15 0" />
        <path d="M164 80q7-6 13 0" />
      </g>
    </g>

    <!-- Day 3 — fog all morning, then the towers -->
    <g v-else-if="name === 'palace'">
      <path
        d="M0 300v-84q120-58 400-34v118Z"
        fill="#0B2233"
      />
      <g fill="#E9944F">
        <path d="M140 128h56v112h-56Z" />
        <path d="M118 96l22-42 22 42Z" />
        <rect
          x="118"
          y="96"
          width="44"
          height="144"
        />
        <path d="M232 84l24-44 24 44Z" />
        <rect
          x="232"
          y="84"
          width="48"
          height="156"
        />
      </g>
      <g
        fill="#0A1C2E"
        opacity=".75"
      >
        <rect
          x="130"
          y="126"
          width="12"
          height="20"
          rx="6"
        />
        <rect
          x="246"
          y="116"
          width="14"
          height="22"
          rx="7"
        />
        <rect
          x="158"
          y="158"
          width="12"
          height="22"
          rx="6"
        />
      </g>
      <rect
        x="118"
        y="236"
        width="162"
        height="8"
        fill="#F0B071"
      />
      <g fill="#061520">
        <path d="M40 300l30-72 30 72Z" />
        <path d="M300 300l26-60 26 60Z" />
        <path d="M352 300l22-48 22 48Z" />
      </g>
      <rect
        y="196"
        width="400"
        height="42"
        fill="#CFE4F0"
        opacity=".18"
      />
    </g>

    <!-- Day 5 — bought figs, ate all the figs -->
    <g v-else-if="name === 'market'">
      <rect
        width="400"
        height="300"
        fill="#12314A"
      />
      <g fill="#061520">
        <rect
          y="196"
          width="400"
          height="104"
        />
      </g>
      <g
        v-for="(x, i) in [20, 150, 280]"
        :key="x"
      >
        <path
          :d="`M${x} 118h100l14 46H${x - 14}Z`"
          :fill="i === 1 ? '#E9944F' : '#CFE4F0'"
          opacity=".9"
        />
        <g
          :fill="i === 1 ? '#0A1C2E' : '#12314A'"
          opacity=".55"
        >
          <rect
            :x="x + 12"
            y="118"
            width="12"
            height="46"
          />
          <rect
            :x="x + 44"
            y="118"
            width="12"
            height="46"
          />
          <rect
            :x="x + 76"
            y="118"
            width="12"
            height="46"
          />
        </g>
        <rect
          :x="x + 10"
          y="196"
          width="76"
          height="48"
          rx="4"
          fill="#0B2233"
        />
        <line
          :x1="x + 10"
          y1="216"
          :x2="x + 86"
          y2="216"
          stroke="#4C86AE"
          stroke-width="2"
        />
        <g
          :fill="i === 1 ? '#E9944F' : '#6FA3C4'"
          opacity=".85"
        >
          <circle
            :cx="x + 26"
            cy="206"
            r="5"
          />
          <circle
            :cx="x + 42"
            cy="206"
            r="5"
          />
          <circle
            :cx="x + 58"
            cy="206"
            r="5"
          />
          <circle
            :cx="x + 34"
            cy="197"
            r="5"
          />
          <circle
            :cx="x + 50"
            cy="197"
            r="5"
          />
        </g>
      </g>
      <g fill="#F0B071">
        <circle
          cx="86"
          cy="94"
          r="7"
        />
        <circle
          cx="200"
          cy="86"
          r="7"
        />
        <circle
          cx="314"
          cy="94"
          r="7"
        />
      </g>
      <path
        d="M0 78q100 28 200 20t200-20"
        stroke="#9CC3DC"
        stroke-width="1.5"
        fill="none"
        opacity=".5"
      />
    </g>

    <!-- Day 5 — dinner ran until the lamps came on -->
    <g v-else-if="name === 'terrace'">
      <rect
        width="400"
        height="300"
        fill="#061520"
      />
      <g :fill="`url(#${skyId})`">
        <path d="M42 240V116a44 44 0 0 1 88 0v124Z" />
        <path d="M156 240V116a44 44 0 0 1 88 0v124Z" />
        <path d="M270 240V116a44 44 0 0 1 88 0v124Z" />
      </g>
      <g
        fill="#0A1C2E"
        opacity=".65"
      >
        <rect
          x="42"
          y="200"
          width="88"
          height="40"
        />
        <rect
          x="156"
          y="200"
          width="88"
          height="40"
        />
        <rect
          x="270"
          y="200"
          width="88"
          height="40"
        />
      </g>
      <g>
        <line
          x1="86"
          y1="40"
          x2="86"
          y2="76"
          stroke="#9CC3DC"
          stroke-width="1.5"
          opacity=".5"
        />
        <line
          x1="200"
          y1="40"
          x2="200"
          y2="92"
          stroke="#9CC3DC"
          stroke-width="1.5"
          opacity=".5"
        />
        <line
          x1="314"
          y1="40"
          x2="314"
          y2="70"
          stroke="#9CC3DC"
          stroke-width="1.5"
          opacity=".5"
        />
        <circle
          cx="86"
          cy="84"
          r="30"
          :fill="`url(#${glowId})`"
        />
        <circle
          cx="200"
          cy="100"
          r="34"
          :fill="`url(#${glowId})`"
        />
        <circle
          cx="314"
          cy="78"
          r="30"
          :fill="`url(#${glowId})`"
        />
        <circle
          cx="86"
          cy="84"
          r="8"
          fill="#F0B071"
        />
        <circle
          cx="200"
          cy="100"
          r="9"
          fill="#F0B071"
        />
        <circle
          cx="314"
          cy="78"
          r="8"
          fill="#F0B071"
        />
      </g>
      <rect
        y="256"
        width="400"
        height="8"
        fill="#9CC3DC"
        opacity=".45"
      />
    </g>

    <!-- Day 6 — last night, rooftops and one moon -->
    <g v-else>
      <g fill="#CFE4F0">
        <circle
          cx="316"
          cy="66"
          r="26"
          opacity=".9"
        />
        <circle
          cx="304"
          cy="58"
          r="24"
          fill="#0B2233"
        />
        <circle
          cx="70"
          cy="52"
          r="2"
          opacity=".8"
        />
        <circle
          cx="128"
          cy="96"
          r="1.6"
          opacity=".6"
        />
        <circle
          cx="196"
          cy="44"
          r="2.2"
          opacity=".8"
        />
        <circle
          cx="252"
          cy="118"
          r="1.6"
          opacity=".5"
        />
        <circle
          cx="42"
          cy="128"
          r="1.8"
          opacity=".6"
        />
        <circle
          cx="356"
          cy="150"
          r="1.6"
          opacity=".5"
        />
        <circle
          cx="160"
          cy="150"
          r="1.4"
          opacity=".45"
        />
      </g>
      <path
        d="M0 300v-96h56v-30h48v46h44v-62h60v62h52v-38h56v52h44v66Z"
        fill="#061520"
      />
      <g
        fill="#F0B071"
        opacity=".85"
      >
        <rect
          x="18"
          y="222"
          width="14"
          height="18"
        />
        <rect
          x="118"
          y="200"
          width="14"
          height="18"
        />
        <rect
          x="212"
          y="182"
          width="14"
          height="18"
        />
        <rect
          x="230"
          y="216"
          width="14"
          height="18"
        />
        <rect
          x="330"
          y="204"
          width="14"
          height="18"
        />
      </g>
    </g>

    <rect
      width="400"
      height="300"
      :fill="`url(#${skyId})`"
      opacity=".12"
    />
  </svg>
</template>

<script setup lang="ts">
import { computed, useId } from 'vue';

/**
 * Toned-cyanotype illustrations for the landing page's sample gallery. Blue ink for everything
 * that is far away, one warm tone for whatever is giving off light — the way a gold-toned
 * cyanotype print actually behaves.
 */
const props = defineProps<{ name: string; label: string }>();

const uid = useId();
const skyId = computed(() => `sky-${uid}`);
const glowId = computed(() => `glow-${uid}`);
const tileId = computed(() => `tile-${uid}`);

const sky = computed<[string, string]>(() => {
  switch (props.name) {
    case 'harbour': return ['#12314A', '#3A6E92'];
    case 'azulejo': return ['#173B58', '#173B58'];
    case 'tram': return ['#17415F', '#5C90B2'];
    case 'cliffs': return ['#2A5B7E', '#B4D3E5'];
    case 'palace': return ['#173C5A', '#6E9BB8'];
    case 'market': return ['#12314A', '#12314A'];
    case 'terrace': return ['#1B4463', '#3A6E92'];
    default: return ['#07182A', '#0F2E48'];
  }
});
</script>

<style scoped>
.cs {
  display: block;
  width: 100%;
  height: 100%;
}
</style>
