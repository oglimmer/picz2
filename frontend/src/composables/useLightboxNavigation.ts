import { ref, type Ref } from "vue";
import { useNotifications } from "./useNotifications";
import type { AlbumFile } from "@/types";

export interface LightboxNavigation {
  selectedFile: Ref<AlbumFile | null>;
  open: (file: AlbumFile) => void;
  next: () => void;
  previous: () => void;
}

/**
 * Which photo the lightbox shows and how the arrow keys move through `files`, wrapping at both
 * ends with a hint so the jump does not look like a glitch. Shared by the owner's gallery and the
 * public share page. `onChange` fires for every move — the recorder uses it to time the slideshow.
 */
export function useLightboxNavigation(
  files: Ref<AlbumFile[]>,
  onChange?: (file: AlbumFile) => void,
): LightboxNavigation {
  const { info } = useNotifications();
  const selectedFile = ref<AlbumFile | null>(null);

  function open(file: AlbumFile): void {
    selectedFile.value = file;
  }

  function step(direction: 1 | -1): void {
    if (!selectedFile.value || files.value.length === 0) return;
    const currentIndex = files.value.findIndex((f) => f.id === selectedFile.value!.id);
    if (currentIndex === -1) return;

    const last = files.value.length - 1;
    if (direction === 1 && currentIndex === last) info("Starting over");
    if (direction === -1 && currentIndex === 0) info("Jumped to the end");

    const nextFile = files.value[(currentIndex + direction + files.value.length) % files.value.length];
    selectedFile.value = nextFile;
    onChange?.(nextFile);
  }

  return {
    selectedFile,
    open,
    next: () => step(1),
    previous: () => step(-1),
  };
}
