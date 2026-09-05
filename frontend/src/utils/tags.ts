import type { AlbumFile, TagCount } from "@/types";

export const HIDDEN_TAG = "hidden";

/**
 * `hidden` is derived, not assigned (D79): the server keeps it on a photo exactly while the photo
 * has no other tag, and refuses to add it or to take a lone one off by hand. So it is not offered
 * where the user picks a tag to put on or take off photos — filtering on it is still fine.
 */
export function isAssignableTag(name: string): boolean {
  return name !== HIDDEN_TAG;
}

/** The tags a user may put on photos: everything but `hidden`. */
export function assignableTags<T extends { name: string }>(tags: T[]): T[] {
  return tags.filter((t) => isAssignableTag(t.name));
}

/** Every tag carried by at least one of `files`, with how many carry it, sorted by name. */
export function countTags(files: AlbumFile[]): TagCount[] {
  if (files.length === 0) return [];
  const counts = new Map<string, number>();
  for (const file of files) {
    for (const tag of file.tags ?? []) {
      counts.set(tag, (counts.get(tag) ?? 0) + 1);
    }
  }
  return Array.from(counts.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => a.name.localeCompare(b.name));
}
