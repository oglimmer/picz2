import type { AlbumFile, TagCount } from "@/types";

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
