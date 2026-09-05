import { describe, expect, it } from "vitest";
import { usePresentationGroups } from "../usePresentationGroups";
import type { AlbumFile, PresentationGroup } from "@/types";

const f = (id: number): AlbumFile =>
  ({ id, albumId: 1, filename: "", path: "", size: 1, uploadedAt: "", tags: ["trip"] }) as AlbumFile;
const g = (id: number, startFileId: number, endFileId: number | null = null): PresentationGroup => ({
  id,
  albumId: 1,
  tag: "trip",
  startFileId,
  endFileId,
  label: `G${id}`,
});

describe("buildSections", () => {
  it("is one headingless section when the tag has no groups", () => {
    const { buildSections } = usePresentationGroups();
    const files = [f(1), f(2)];
    expect(buildSections(files, "trip")).toEqual([{ group: null, files, closed: false }]);
    expect(buildSections([], "trip")).toEqual([]);
  });

  it("opens a section at each anchor and drops an empty lead", () => {
    const api = usePresentationGroups();
    api.groups.value = [g(10, 1), g(11, 3)];
    const sections = api.buildSections([f(1), f(2), f(3), f(4)], "trip");
    expect(sections.map((s) => [s.group?.id ?? null, s.files.map((x) => x.id), s.closed])).toEqual([
      [10, [1, 2], false],
      [11, [3, 4], false],
    ]);
  });

  it("closes a group on its end image and lets the rest fall into a headingless run", () => {
    const api = usePresentationGroups();
    api.groups.value = [g(10, 2, 3)];
    const sections = api.buildSections([f(1), f(2), f(3), f(4)], "trip");
    expect(sections.map((s) => [s.group?.id ?? null, s.files.map((x) => x.id), s.closed])).toEqual([
      [null, [1], false],
      [10, [2, 3], true],
      [null, [4], false],
    ]);
  });

  it("ignores an end that sits in front of its own start", () => {
    const api = usePresentationGroups();
    api.groups.value = [g(10, 3, 1)];
    const sections = api.buildSections([f(1), f(2), f(3), f(4)], "trip");
    expect(sections.at(-1)?.closed).toBe(false);
    expect(sections.at(-1)?.files.map((x: AlbumFile) => x.id)).toEqual([3, 4]);
  });
});

describe("groupContextFor", () => {
  it("names the group and the position for an image inside one, null outside", () => {
    const api = usePresentationGroups();
    api.groups.value = [g(10, 2)];
    const sections = api.buildSections([f(1), f(2), f(3)], "trip");
    expect(api.groupContextFor(sections, 3)).toEqual({ id: 10, label: "G10", text: null, position: 2, total: 2 });
    expect(api.groupContextFor(sections, 1)).toBeNull();
    expect(api.groupContextFor(sections, null)).toBeNull();
  });
});
