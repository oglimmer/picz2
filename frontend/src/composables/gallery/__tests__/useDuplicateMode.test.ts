import { describe, expect, it, vi } from "vitest";
import { ref } from "vue";
import { useDuplicateMode } from "../useDuplicateMode";
import type { AlbumFile } from "@/types";

const f = (id: number, originalName: string): AlbumFile =>
  ({ id, albumId: 1, filename: `${id}.jpg`, originalName, path: "", size: 1, uploadedAt: "", tags: [] }) as AlbumFile;

describe("useDuplicateMode", () => {
  it("shows only files sharing a name and pre-selects every copy but the first", () => {
    const files = ref([f(1, "a.jpg"), f(2, "b.jpg"), f(3, "a.jpg"), f(4, "a.jpg"), f(5, "c.jpg")]);
    const mode = useDuplicateMode({ files, deleteMany: vi.fn() });
    expect(mode.displayedFiles.value).toBe(files.value);

    mode.toggleMode();
    expect(mode.displayedFiles.value.map((x) => x.id)).toEqual([1, 3, 4]);
    expect([...mode.selected.value].sort()).toEqual([3, 4]);
  });

  it("never flags iOS's FullSizeRender.heic", () => {
    const files = ref([f(1, "FullSizeRender.heic"), f(2, "fullsizerender.HEIC")]);
    const mode = useDuplicateMode({ files, deleteMany: vi.fn() });
    mode.toggleMode();
    expect(mode.displayedFiles.value).toEqual([]);
    expect(mode.selected.value.size).toBe(0);
  });

  it("deletes the selection, keeps failures selected, and leaves the mode when nothing is left", async () => {
    const files = ref([f(1, "a.jpg"), f(2, "a.jpg")]);
    const deleteMany = vi.fn(async (ids: number[]) => {
      files.value = files.value.filter((x) => !ids.includes(x.id));
      return [] as number[];
    });
    const onActivate = vi.fn();
    const mode = useDuplicateMode({ files, deleteMany, onActivate });
    mode.toggleMode();
    expect(onActivate).toHaveBeenCalled();
    await mode.deleteSelected();
    expect(deleteMany).toHaveBeenCalledWith([2]);
    expect(mode.active.value).toBe(false);
  });

  it("a cancelled confirm leaves everything as it was", async () => {
    const files = ref([f(1, "a.jpg"), f(2, "a.jpg")]);
    const mode = useDuplicateMode({ files, deleteMany: vi.fn(async () => null) });
    mode.toggleMode();
    await mode.deleteSelected();
    expect(mode.active.value).toBe(true);
    expect([...mode.selected.value]).toEqual([2]);
  });
});
