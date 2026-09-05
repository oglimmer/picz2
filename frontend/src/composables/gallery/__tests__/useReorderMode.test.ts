import { describe, expect, it, vi } from "vitest";
import { ref } from "vue";
import { useReorderMode } from "../useReorderMode";
import type { AlbumFile } from "@/types";

const f = (id: number): AlbumFile =>
  ({ id, albumId: 1, filename: "", path: "", size: 1, uploadedAt: "", tags: [] }) as AlbumFile;
const ids = (files: AlbumFile[]) => files.map((x) => x.id);

describe("useReorderMode", () => {
  it("moves the selection after a target and to the top, persisting each time", async () => {
    const files = ref([f(1), f(2), f(3), f(4), f(5)]);
    const reorderFiles = vi.fn(async () => {});
    const mode = useReorderMode({ files, reorderFiles, reloadFiles: vi.fn() });

    mode.toggleMode();
    mode.toggleSelection(1);
    mode.toggleSelection(2);
    await mode.moveSelectedAfter(4);
    expect(ids(files.value)).toEqual([3, 4, 1, 2, 5]);
    expect(reorderFiles).toHaveBeenLastCalledWith([3, 4, 1, 2, 5]);
    expect(mode.selected.value.size).toBe(0);

    mode.toggleSelection(5);
    await mode.moveSelectedToTop();
    expect(ids(files.value)).toEqual([5, 3, 4, 1, 2]);
  });

  it("ignores a drop onto one of the selected files", async () => {
    const files = ref([f(1), f(2), f(3)]);
    const reorderFiles = vi.fn(async () => {});
    const mode = useReorderMode({ files, reorderFiles, reloadFiles: vi.fn() });
    mode.toggleMode();
    mode.toggleSelection(1);
    await mode.moveSelectedAfter(1);
    expect(reorderFiles).not.toHaveBeenCalled();
  });

  it("reloads from the server when the reorder is refused", async () => {
    const files = ref([f(1), f(2), f(3)]);
    const reloadFiles = vi.fn(async () => {});
    const mode = useReorderMode({
      files,
      reorderFiles: vi.fn(async () => {
        throw new Error("409");
      }),
      reloadFiles,
    });
    await mode.onDrop(new Event("drop") as DragEvent, 0);
    // No drag in flight: nothing to do.
    expect(reloadFiles).not.toHaveBeenCalled();

    mode.onDragStart(new Event("dragstart") as DragEvent, 2);
    await mode.onDrop(new Event("drop") as DragEvent, 0);
    expect(ids(files.value)).toEqual([3, 1, 2]); // optimistic order …
    expect(reloadFiles).toHaveBeenCalled(); // … then the server's truth is fetched back
    expect(mode.draggingIndex.value).toBeNull();
  });

  it("switching the mode on tells the caller so a rival mode can switch off", () => {
    const onActivate = vi.fn();
    const mode = useReorderMode({ files: ref([]), reorderFiles: vi.fn(), reloadFiles: vi.fn(), onActivate });
    mode.toggleMode();
    expect(onActivate).toHaveBeenCalledTimes(1);
    mode.toggleMode();
    expect(mode.active.value).toBe(false);
    expect(onActivate).toHaveBeenCalledTimes(1);
  });
});
