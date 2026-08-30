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

/**
 * Format date to relative or absolute format
 */
export function formatDate(dateString: string): string {
  const date = new Date(dateString);
  // A missing or unparseable timestamp used to reach the UI as the literal string
  // "Invalid Date"; render nothing instead and let the caller omit the element.
  if (Number.isNaN(date.getTime())) return "";
  const now = new Date();
  const diffTime = Math.abs(now.getTime() - date.getTime());
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

  if (diffDays === 1) return "Today";
  if (diffDays === 2) return "Yesterday";
  if (diffDays < 7) return `${diffDays - 1} days ago`;

  return date.toLocaleDateString();
}

/**
 * Check if file is a video based on mimetype
 */
export function isVideo(file: AlbumFile | { mimetype?: string }): boolean {
  if (!file || !file.mimetype) return false;
  return file.mimetype.startsWith("video/");
}
