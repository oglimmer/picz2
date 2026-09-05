import { describe, expect, it } from "vitest";
import { countTags } from "../tags";
import type { AlbumFile } from "@/types";

const file = (id: number, tags?: string[]): AlbumFile =>
  ({ id, albumId: 1, filename: `${id}.jpg`, path: "", size: 1, uploadedAt: "", tags }) as AlbumFile;

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
