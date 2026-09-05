import { describe, expect, it } from "vitest";
import { assignableTags, countTags, isAssignableTag } from "../tags";
import type { AlbumFile } from "@/types";

const file = (id: number, tags?: string[]): AlbumFile =>
  ({ id, albumId: 1, filename: `${id}.jpg`, path: "", size: 1, uploadedAt: "", tags }) as AlbumFile;

describe("assignableTags", () => {
  it("keeps every tag but hidden, all included", () => {
    const tags = [
      { id: 1, name: "all" },
      { id: 2, name: "hidden" },
      { id: 3, name: "beach" },
    ];
    expect(assignableTags(tags).map((t) => t.name)).toEqual(["all", "beach"]);
    expect(isAssignableTag("hidden")).toBe(false);
    expect(isAssignableTag("all")).toBe(true);
  });

  it("does not treat a look-alike as the system tag", () => {
    expect(isAssignableTag("hidden-42")).toBe(true);
    expect(isAssignableTag("Hidden")).toBe(true);
  });
});

describe("countTags", () => {
  it("counts every tag across the files, sorted by name", () => {
    expect(countTags([file(1, ["b", "a"]), file(2, ["a"]), file(3)])).toEqual([
      { name: "a", count: 2 },
      { name: "b", count: 1 },
    ]);
  });

  it("is empty for no files and for untagged files", () => {
    expect(countTags([])).toEqual([]);
    expect(countTags([file(1), file(2, [])])).toEqual([]);
  });
});
