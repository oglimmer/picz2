import { describe, expect, it, vi } from "vitest";
import { ref } from "vue";
import { useLightboxNavigation } from "../useLightboxNavigation";
import { useNotifications } from "../useNotifications";
import type { AlbumFile } from "@/types";

const f = (id: number): AlbumFile =>
  ({ id, albumId: 1, filename: "", path: "", size: 1, uploadedAt: "", tags: [] }) as AlbumFile;

/** A text card (D86): an entry with no pixels at any size, so the lightbox must step over it. */
const card = (id: number): AlbumFile => ({ ...f(id), kind: "TEXT_CARD" }) as AlbumFile;

describe("useLightboxNavigation", () => {
  it("steps through the files and wraps at both ends with a hint", () => {
    const files = ref([f(1), f(2), f(3)]);
    const onChange = vi.fn();
    const nav = useLightboxNavigation(files, onChange);
    const { notifications } = useNotifications();
    notifications.value.splice(0);

    nav.open(files.value[2]);
    nav.next();
    expect(nav.selectedFile.value?.id).toBe(1);
    expect(notifications.value.at(-1)?.message).toBe("Starting over");
    nav.previous();
    expect(nav.selectedFile.value?.id).toBe(3);
    expect(notifications.value.at(-1)?.message).toBe("Jumped to the end");
    expect(onChange).toHaveBeenCalledTimes(2);
  });

  /**
   * D86: the lightbox draws a card as a full-screen chapter page, so it is a stop on the walk
   * like any photo — a reader working through an album zoomed in has to meet its headings.
   */
  it("steps onto a text card like any other entry", () => {
    const files = ref([f(1), card(2), f(3)]);
    const nav = useLightboxNavigation(files);

    nav.open(files.value[0]);
    nav.next();
    expect(nav.selectedFile.value?.id).toBe(2);
    nav.next();
    expect(nav.selectedFile.value?.id).toBe(3);
    nav.previous();
    expect(nav.selectedFile.value?.id).toBe(2);
  });

  it("does nothing while closed or when the file vanished from the list", () => {
    const files = ref([f(1), f(2)]);
    const nav = useLightboxNavigation(files);
    nav.next();
    expect(nav.selectedFile.value).toBeNull();
    nav.open(f(99));
    nav.next();
    expect(nav.selectedFile.value?.id).toBe(99);
  });
});
