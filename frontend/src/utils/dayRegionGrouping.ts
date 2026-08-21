import type { AlbumFile } from "@/types";

/**
 * "By day and region" grouping — one section per calendar day, and inside it one sub-section
 * per place, where a place is a set of photos that all sit within `radiusMeters` of each other.
 *
 * The clustering is deliberately *not* a plain "grow a blob while the next photo is near the
 * last one" pass: that chains, so a walk across a city merges into one 20 km "region" even
 * though its ends are nowhere near each other. What runs here is a complete-linkage
 * agglomerative clustering with the merge threshold as a hard cap: two clusters merge only when
 * *every* cross pair is within the radius, so a finished cluster is guaranteed to have a
 * diameter of at most `radiusMeters`. Merges are attempted shortest-edge-first, which is what
 * makes the greedy pass produce the same natural groups a full O(n³) run would.
 */

/** Default region size: photos in one cluster are never more than this far apart. */
export const DEFAULT_REGION_RADIUS_METERS = 2000;

/**
 * Above this many located photos in a single day the exact pass is skipped for a leader pass
 * (see `leaderCluster`). Exact merging is O(n²) in both candidate pairs and cross-pair checks,
 * which is nothing for a normal day out and a frozen tab for a bulk import of a whole year
 * stamped with one date.
 */
const EXACT_PASS_LIMIT = 1500;

const EARTH_RADIUS_METERS = 6_371_008.8;

export interface LatLng {
  lat: number;
  lng: number;
}

export interface RegionCluster {
  /** Stable key for `v-for`, derived from the day and the cluster's first file. */
  key: string;
  files: AlbumFile[];
  /** Mean position of the cluster's photos, or null for the "no location" bucket. */
  center: LatLng | null;
  /** Largest distance between any two photos in the cluster, in metres (0 for a single photo). */
  spreadMeters: number;
  /** False for the one bucket per day that collects photos without GPS coordinates. */
  located: boolean;
}

export interface DayGroup {
  /** Local calendar day, `YYYY-MM-DD`; `"unknown"` when a photo carries no usable date. */
  key: string;
  /** Local midnight of that day, or null for the unknown-date group. */
  date: Date | null;
  clusters: RegionCluster[];
  count: number;
}

/** Great-circle distance in metres. */
export function haversineMeters(a: LatLng, b: LatLng): number {
  const toRad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * toRad;
  const dLng = (b.lng - a.lng) * toRad;
  const lat1 = a.lat * toRad;
  const lat2 = b.lat * toRad;
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** The capture position of a file, or null when it carries no coordinates. */
export function fileLatLng(file: AlbumFile): LatLng | null {
  if (typeof file.gpsLatitude !== "number" || typeof file.gpsLongitude !== "number") return null;
  if (Number.isNaN(file.gpsLatitude) || Number.isNaN(file.gpsLongitude)) return null;
  return { lat: file.gpsLatitude, lng: file.gpsLongitude };
}

/** When the photo was taken, preferring EXIF over the upload timestamp. */
function captureDate(file: AlbumFile): Date | null {
  const raw = file.exifDateTimeOriginal || file.uploadedAt;
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** Local `YYYY-MM-DD`; local, not UTC, so an evening photo stays on the evening's date. */
function dayKey(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

/**
 * Local flat projection in metres around `origin`. Over a few kilometres the error against the
 * ellipsoid is centimetres, and it turns the grid bucketing below into plain arithmetic.
 */
function project(point: LatLng, origin: LatLng): { x: number; y: number } {
  const toRad = Math.PI / 180;
  return {
    x: (point.lng - origin.lng) * toRad * EARTH_RADIUS_METERS * Math.cos(origin.lat * toRad),
    y: (point.lat - origin.lat) * toRad * EARTH_RADIUS_METERS,
  };
}

interface Cluster {
  members: number[];
  spread: number;
}

/**
 * Groups indices of `points` so that no cluster is wider than `radius`.
 *
 * Candidate pairs come from a uniform grid with cells one radius wide, so only the 3×3 cell
 * neighbourhood of each point is examined instead of all pairs. Those pairs are then merged
 * shortest-first under the complete-linkage rule.
 *
 * @returns clusters as arrays of indices into `points`, each with its own diameter
 */
function completeLinkageCluster(points: LatLng[], radius: number): Cluster[] {
  const n = points.length;
  if (n === 0) return [];
  if (n === 1) return [{ members: [0], spread: 0 }];

  const origin = points[0];
  const flat = points.map((p) => project(p, origin));

  // --- Candidate pairs via a radius-wide grid ------------------------------------------------
  const cells = new Map<string, number[]>();
  const cellOf = (i: number) => ({
    cx: Math.floor(flat[i].x / radius),
    cy: Math.floor(flat[i].y / radius),
  });
  for (let i = 0; i < n; i++) {
    const { cx, cy } = cellOf(i);
    const key = `${cx}:${cy}`;
    const bucket = cells.get(key);
    if (bucket) bucket.push(i);
    else cells.set(key, [i]);
  }

  const edges: { a: number; b: number; d: number }[] = [];
  for (let i = 0; i < n; i++) {
    const { cx, cy } = cellOf(i);
    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) {
        const bucket = cells.get(`${cx + dx}:${cy + dy}`);
        if (!bucket) continue;
        for (const j of bucket) {
          if (j <= i) continue; // each unordered pair once
          const d = haversineMeters(points[i], points[j]);
          if (d <= radius) edges.push({ a: i, b: j, d });
        }
      }
    }
  }
  edges.sort((p, q) => p.d - q.d);

  // --- Merge shortest-first, but only when the whole merged set stays inside the radius -------
  const owner = new Int32Array(n); // index -> cluster id
  const clusters: (Cluster | null)[] = [];
  for (let i = 0; i < n; i++) {
    owner[i] = i;
    clusters.push({ members: [i], spread: 0 });
  }

  for (const edge of edges) {
    const idA = owner[edge.a];
    const idB = owner[edge.b];
    if (idA === idB) continue;
    const a = clusters[idA]!;
    const b = clusters[idB]!;

    let worst = Math.max(a.spread, b.spread);
    let joinable = true;
    for (const i of a.members) {
      for (const j of b.members) {
        const d = haversineMeters(points[i], points[j]);
        if (d > radius) {
          joinable = false;
          break;
        }
        if (d > worst) worst = d;
      }
      if (!joinable) break;
    }
    if (!joinable) continue;

    // Fold the smaller side in, so the owner rewrite stays cheap.
    const [keepId, dropId] =
      a.members.length >= b.members.length ? [idA, idB] : [idB, idA];
    const keep = clusters[keepId]!;
    const drop = clusters[dropId]!;
    for (const i of drop.members) owner[i] = keepId;
    keep.members.push(...drop.members);
    keep.spread = worst;
    clusters[dropId] = null;
  }

  return clusters.filter((c): c is Cluster => c !== null);
}

/**
 * Fallback for very large days: one pass that opens a new cluster whenever a photo is further
 * than half a radius from every existing cluster's leader. Half, because two photos on opposite
 * sides of a leader are then still within a full radius of each other — the diameter guarantee
 * of the exact pass survives, only the choice of groups is cruder.
 */
function leaderCluster(points: LatLng[], radius: number): Cluster[] {
  const half = radius / 2;
  const leaders: { at: LatLng; cluster: Cluster }[] = [];
  for (let i = 0; i < points.length; i++) {
    let best: { at: LatLng; cluster: Cluster } | null = null;
    let bestDistance = Infinity;
    for (const leader of leaders) {
      const d = haversineMeters(points[i], leader.at);
      if (d <= half && d < bestDistance) {
        best = leader;
        bestDistance = d;
      }
    }
    if (best) {
      best.cluster.members.push(i);
      best.cluster.spread = Math.max(best.cluster.spread, bestDistance * 2);
    } else {
      leaders.push({ at: points[i], cluster: { members: [i], spread: 0 } });
    }
  }
  return leaders.map((l) => l.cluster);
}

function centroid(points: LatLng[]): LatLng {
  // Mean of unit vectors, so a cluster straddling the ±180° meridian still lands in the middle.
  const toRad = Math.PI / 180;
  let x = 0;
  let y = 0;
  let z = 0;
  for (const p of points) {
    const lat = p.lat * toRad;
    const lng = p.lng * toRad;
    x += Math.cos(lat) * Math.cos(lng);
    y += Math.cos(lat) * Math.sin(lng);
    z += Math.sin(lat);
  }
  const n = points.length || 1;
  x /= n;
  y /= n;
  z /= n;
  const hyp = Math.sqrt(x * x + y * y);
  return {
    lat: (Math.atan2(z, hyp) * 180) / Math.PI,
    lng: (Math.atan2(y, x) * 180) / Math.PI,
  };
}

/**
 * Splits files into day sections, each split again into regions of at most `radiusMeters`.
 *
 * Days, the clusters inside a day, and the files inside a cluster all keep the order they had
 * in `files` (the album's own order): the grouping re-shelves the gallery, it does not re-sort
 * it. Photos without a usable date land in a trailing "unknown" day; photos without coordinates
 * land in a trailing bucket of their own day.
 */
export function groupByDayAndRegion(
  files: AlbumFile[],
  radiusMeters: number = DEFAULT_REGION_RADIUS_METERS,
): DayGroup[] {
  const days = new Map<string, { date: Date | null; files: AlbumFile[] }>();

  for (const file of files) {
    const date = captureDate(file);
    const key = date ? dayKey(date) : "unknown";
    let day = days.get(key);
    if (!day) {
      day = {
        date: date ? new Date(date.getFullYear(), date.getMonth(), date.getDate()) : null,
        files: [],
      };
      days.set(key, day);
    }
    day.files.push(file);
  }

  const groups: DayGroup[] = [];
  for (const [key, day] of days) {
    const located: AlbumFile[] = [];
    const points: LatLng[] = [];
    const unlocated: AlbumFile[] = [];
    for (const file of day.files) {
      const at = fileLatLng(file);
      if (at) {
        located.push(file);
        points.push(at);
      } else {
        unlocated.push(file);
      }
    }

    const raw =
      points.length > EXACT_PASS_LIMIT
        ? leaderCluster(points, radiusMeters)
        : completeLinkageCluster(points, radiusMeters);

    // Album order decides which cluster comes first and how photos sit inside it.
    for (const cluster of raw) cluster.members.sort((a, b) => a - b);
    raw.sort((a, b) => a.members[0] - b.members[0]);

    const clusters: RegionCluster[] = raw.map((cluster) => {
      const clusterFiles = cluster.members.map((i) => located[i]);
      return {
        key: `${key}:loc:${clusterFiles[0].id}`,
        files: clusterFiles,
        center: centroid(cluster.members.map((i) => points[i])),
        spreadMeters: cluster.spread,
        located: true,
      };
    });

    if (unlocated.length > 0) {
      clusters.push({
        key: `${key}:nogps`,
        files: unlocated,
        center: null,
        spreadMeters: 0,
        located: false,
      });
    }

    groups.push({ key, date: day.date, clusters, count: day.files.length });
  }

  return groups;
}

/** "1.2 km" / "800 m" — the span quoted next to a region heading. */
export function formatDistance(meters: number): string {
  if (!Number.isFinite(meters) || meters <= 0) return "0 m";
  if (meters < 1000) return `${Math.round(meters / 10) * 10} m`;
  return `${(meters / 1000).toFixed(1)} km`;
}

/** "48.137, 11.575" — the region label used when no place name is available. */
export function formatCoordinates(at: LatLng): string {
  return `${at.lat.toFixed(3)}, ${at.lng.toFixed(3)}`;
}

/** "Monday, 4 May 2026" in the browser's locale; "Date unknown" for the trailing group. */
export function formatDayLabel(day: DayGroup): string {
  if (!day.date) return "Date unknown";
  return day.date.toLocaleDateString(undefined, {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}
