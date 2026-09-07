import { ref, type Ref } from "vue";
import { useNotifications } from "./useNotifications";
import type { Album } from "@/types";

export interface AlbumShelfOrderDeps {
  albums: Ref<Album[]>;
  reorderAlbums: (albumIds: number[]) => Promise<void>;
  reloadAlbums: () => Promise<void>;
}

export interface AlbumShelfOrder {
  draggingIndex: Ref<number | null>;
  dragOverIndex: Ref<number | null>;
  onDragStart: (event: DragEvent, index: number) => void;
  onDragOver: (event: DragEvent, index: number) => void;
  onDragEnter: (event: DragEvent, index: number) => void;
  onDrop: (event: DragEvent, dropIndex: number) => Promise<void>;
  onDragEnd: () => void;
}

/**
 * Drag one album tile onto another to put the shelf in a new order. The new order is shown at
 * once and then sent; a refused save reloads the shelf, so the grid never keeps an order the
 * server did not take. Mirrors `useReorderMode`, which does the same for photos inside an album.
 *
 * `dragOverIndex` — the slot the dashed outline marks — is moved by entering a tile and cleared
 * only when the drag ends. There is deliberately no dragleave: the badges and buttons on a tile
 * are children that fire their own leave events, so clearing on leave made the outline blink as
 * the pointer crossed the tile it was already over.
 */
export function useAlbumShelfOrder(deps: AlbumShelfOrderDeps): AlbumShelfOrder {
  const { error } = useNotifications();
  const draggingIndex = ref<number | null>(null);
  const dragOverIndex = ref<number | null>(null);

  function onDragStart(event: DragEvent, index: number): void {
    draggingIndex.value = index;
    if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
  }

  function onDragOver(event: DragEvent, index: number): void {
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
    dragOverIndex.value = index;
  }

  function onDragEnter(event: DragEvent, index: number): void {
    event.preventDefault();
    dragOverIndex.value = index;
  }

  async function onDrop(event: DragEvent, dropIndex: number): Promise<void> {
    event.preventDefault();
    event.stopPropagation();
    const dragIndex = draggingIndex.value;
    onDragEnd();
    if (dragIndex === null || dragIndex === dropIndex) return;

    const previous = deps.albums.value;
    const next = [...previous];
    const [dragged] = next.splice(dragIndex, 1);
    next.splice(dropIndex, 0, dragged);
    deps.albums.value = next;

    try {
      await deps.reorderAlbums(next.map((a) => a.id));
    } catch (err) {
      await deps.reloadAlbums();
      error(`Error reordering albums: ${err instanceof Error ? err.message : "Unknown error"}`);
    }
  }

  function onDragEnd(): void {
    draggingIndex.value = null;
    dragOverIndex.value = null;
  }

  return {
    draggingIndex,
    dragOverIndex,
    onDragStart,
    onDragOver,
    onDragEnter,
    onDrop,
    onDragEnd,
  };
}
