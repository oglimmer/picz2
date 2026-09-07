import type { AlbumFile } from "@/types";

/**
 * Format bytes to human-readable size.
 *
 * The unit list runs to PB and the index is clamped to it. It used to stop at GB, which was fine
 * while this only ever formatted one photo — then a storage quota of 1 PB rendered as
 * "1 undefined", because the computed index ran off the end of the array. Clamping keeps a very
 * large number readable ("1024 TB") instead of unreadable, and the same clamp at the bottom stops
 * a fractional byte count from producing a negative index.
 */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 Bytes";
  const k = 1024;
  const sizes = ["Bytes", "KB", "MB", "GB", "TB", "PB"];
  const exponent = Math.floor(Math.log(bytes) / Math.log(k));
  const i = Math.min(Math.max(exponent, 0), sizes.length - 1);
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + " " + sizes[i];
}

/** Local midnight of the day `date` falls on, in ms. */
function startOfLocalDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

/**
 * Format date to relative or absolute format.
 *
 * Counts whole calendar days, not 24-hour blocks, so 23:50 yesterday is "Yesterday" and not
 * "Today". The difference is signed on purpose: a camera with a wrong clock can stamp a photo in
 * the future, and that must not read as "Today" — it falls through to the plain date.
 */
export function formatDate(dateString: string): string {
  const date = new Date(dateString);
  // A missing or unparseable timestamp used to reach the UI as the literal string
  // "Invalid Date"; render nothing instead and let the caller omit the element.
  if (Number.isNaN(date.getTime())) return "";
  const dayMs = 24 * 60 * 60 * 1000;
  const diffDays = Math.round((startOfLocalDay(new Date()) - startOfLocalDay(date)) / dayMs);

  if (diffDays === 0) return "Today";
  if (diffDays === 1) return "Yesterday";
  if (diffDays > 1 && diffDays < 7) return `${diffDays} days ago`;

  return date.toLocaleDateString();
}

/**
 * True for a text card (D86) — an album entry that carries a chapter heading instead of pixels.
 *
 * Reads the server's `kind`, not the mime type: the server derives one from the other and is the
 * only place that decision belongs. A row with no `kind` is a photo, which is the safe way round
 * — mistaking a photo for a card would draw text over a picture that never gets rendered.
 */
export function isTextCard(file: AlbumFile | { kind?: string } | null | undefined): boolean {
  return file?.kind === "TEXT_CARD";
}

/**
 * The photo a text card borrows its background from (D86): the next entry after `index` that is
 * an actual picture. A card at the end of the album, or one followed only by other cards, gets
 * nothing back and is drawn on a plain ground.
 *
 * Videos count. A video has a thumbnail like a photo does, and blurred out it reads the same.
 */
export function backgroundPhotoFor<T extends { kind?: string; publicToken?: string }>(
  files: readonly T[],
  index: number,
): T | null {
  for (let i = index + 1; i < files.length; i++) {
    const candidate = files[i];
    if (!isTextCard(candidate) && candidate.publicToken) return candidate;
  }
  return null;
}

/**
 * Check if file is a video based on mimetype
 */
export function isVideo(file: AlbumFile | { mimetype?: string }): boolean {
  if (!file || !file.mimetype) return false;
  return file.mimetype.startsWith("video/");
}
