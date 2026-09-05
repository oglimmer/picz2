import { describe, expect, it } from "vitest";
import { ref } from "vue";
import { useSelection } from "../useSelection";
import type { AlbumFile } from "@/types";

const f = (id: number): AlbumFile =>
  ({ id, albumId: 1, filename: "", path: "", size: 1, uploadedAt: "", tags: [] }) as AlbumFile;

describe("useSelection", () => {
  it("toggles single files and extends a range with shift", () => {
    const files = ref([f(1), f(2), f(3), f(4), f(5)]);
    const sel = useSelection(files);
    sel.toggle(2, 1);
    sel.toggle(4, 3, true);
    expect([...sel.selectedFileIds.value].sort()).toEqual([2, 3, 4]);
    sel.toggle(3, 2);
    expect(sel.selectedFileIds.value.has(3)).toBe(false);
    expect(sel.selectionActive.value).toBe(true);
  });

  it("refuses a range from an unknown anchor and treats it as a plain toggle", () => {
    const files = ref([f(1), f(2), f(3)]);
    const sel = useSelection(files);
    sel.toggle(1, 0);
    sel.toggle(3, -1, true);
    expect([...sel.selectedFileIds.value].sort()).toEqual([1, 3]);
  });

  it("handles Escape and Ctrl/Cmd+A", () => {
    const files = ref([f(1), f(2)]);
    const sel = useSelection(files);
    expect(sel.handleKeydown(new KeyboardEvent("keydown", { key: "a", ctrlKey: true }))).toBe(true);
    expect(sel.selectedFileIds.value.size).toBe(2);
    expect(sel.handleKeydown(new KeyboardEvent("keydown", { key: "Escape" }))).toBe(true);
    expect(sel.selectedFileIds.value.size).toBe(0);
    // Escape with nothing selected is not ours to consume (the lightbox may want it).
    expect(sel.handleKeydown(new KeyboardEvent("keydown", { key: "Escape" }))).toBe(false);
  });
});
