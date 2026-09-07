import { describe, expect, it, vi } from "vitest";
import { ref } from "vue";
import { useAlbumShelfOrder } from "../useAlbumShelfOrder";
import type { Album } from "@/types";

const a = (id: number): Album => ({ id, name: `Album ${id}` }) as Album;
const ids = (albums: Album[]) => albums.map((x) => x.id);

describe("useAlbumShelfOrder", () => {
  it("moves the dragged tile to the drop position and saves the new order", async () => {
    const albums = ref([a(1), a(2), a(3), a(4)]);
    const reorderAlbums = vi.fn(async () => {});
    const shelf = useAlbumShelfOrder({ albums, reorderAlbums, reloadAlbums: vi.fn() });

    shelf.onDragStart(new Event("dragstart") as DragEvent, 3);
    await shelf.onDrop(new Event("drop") as DragEvent, 0);

    expect(ids(albums.value)).toEqual([4, 1, 2, 3]);
    expect(reorderAlbums).toHaveBeenCalledWith([4, 1, 2, 3]);
    expect(shelf.draggingIndex.value).toBeNull();
    expect(shelf.dragOverIndex.value).toBeNull();
  });

  it("does nothing without a drag in flight, or when dropped on itself", async () => {
    const albums = ref([a(1), a(2)]);
    const reorderAlbums = vi.fn(async () => {});
    const shelf = useAlbumShelfOrder({ albums, reorderAlbums, reloadAlbums: vi.fn() });

    await shelf.onDrop(new Event("drop") as DragEvent, 1);
    shelf.onDragStart(new Event("dragstart") as DragEvent, 1);
    await shelf.onDrop(new Event("drop") as DragEvent, 1);

    expect(reorderAlbums).not.toHaveBeenCalled();
    expect(ids(albums.value)).toEqual([1, 2]);
  });

  it("reloads the shelf when the save is refused", async () => {
    const albums = ref([a(1), a(2), a(3)]);
    const reloadAlbums = vi.fn(async () => {});
    const shelf = useAlbumShelfOrder({
      albums,
      reorderAlbums: vi.fn(async () => {
        throw new Error("500");
      }),
      reloadAlbums,
    });

    shelf.onDragStart(new Event("dragstart") as DragEvent, 0);
    await shelf.onDrop(new Event("drop") as DragEvent, 2);

    expect(ids(albums.value)).toEqual([2, 3, 1]); // shown at once …
    expect(reloadAlbums).toHaveBeenCalled(); // … then the server's truth is fetched back
  });

  it("keeps the outline on the last tile entered until the drag ends", () => {
    const albums = ref([a(1), a(2)]);
    const shelf = useAlbumShelfOrder({
      albums,
      reorderAlbums: vi.fn(async () => {}),
      reloadAlbums: vi.fn(),
    });

    shelf.onDragEnter(new Event("dragenter") as DragEvent, 1);
    expect(shelf.dragOverIndex.value).toBe(1);

    // A tile's own badges and buttons fire events of their own; nothing but entering another
    // tile moves the outline.
    shelf.onDragOver(new Event("dragover") as DragEvent, 1);
    expect(shelf.dragOverIndex.value).toBe(1);

    shelf.onDragEnd();
    expect(shelf.dragOverIndex.value).toBeNull();
  });
});
