import { ref, type Ref } from "vue";
import { useNotifications } from "../useNotifications";
import { useUpload } from "../useUpload";
import type { Album, AlbumFile } from "@/types";

export interface UploadProgress {
  current: number;
  total: number;
  status: string;
  currentFileName: string;
}

export interface UploadFlowDeps {
  album: Ref<Album | null>;
  files: Ref<AlbumFile[]>;
  reloadFiles: () => Promise<void>;
}

export interface UploadFlow {
  uploading: Ref<boolean>;
  progress: Ref<UploadProgress>;
  uploadFiles: (selected: File[]) => Promise<void>;
}

const idle = (): UploadProgress => ({ current: 0, total: 0, status: "", currentFileName: "" });

/** Uploading a batch of files from the gallery's picker, one at a time, with a progress overlay. */
export function useUploadFlow(deps: UploadFlowDeps): UploadFlow {
  const { uploadFile } = useUpload();
  const { success, warning, error } = useNotifications();
  const uploading = ref(false);
  const progress = ref<UploadProgress>(idle());

  async function uploadFiles(selected: File[]): Promise<void> {
    if (selected.length === 0) return;
    if (!deps.album.value) {
      warning("No album selected");
      return;
    }
    const albumId = deps.album.value.id;

    uploading.value = true;
    progress.value = { current: 0, total: selected.length, status: "Preparing upload...", currentFileName: "" };

    let successCount = 0;
    const errors: string[] = [];
    // TUS post-finish race: tusd 2.x sends the PATCH 204 to the client *before* invoking the
    // post-finish hook (despite the docs claiming it's synchronous). So uploadFile() resolves
    // ~200-500ms before the file_metadata row exists. Snapshot the count before the loop and poll
    // the file list after, until the row(s) show up or we hit the timeout. Multipart doesn't have
    // this race (the row is committed by the time /api/upload returns), but the same
    // poll-until-visible logic is harmless.
    const initialCount = deps.files.value.length;

    try {
      for (let i = 0; i < selected.length; i++) {
        const file = selected[i];
        progress.value.current = i;
        progress.value.currentFileName = file.name;
        progress.value.status = `Uploading ${file.name}...`;
        try {
          await uploadFile(file, albumId, {
            onProgress: (fraction) => {
              // TUS surfaces real bytes; multipart surfaces 0/1 bookends. Either way a percentage
              // on the status line keeps a big file from looking stuck.
              progress.value.status = `Uploading ${file.name}... ${Math.round(fraction * 100)}%`;
            },
          });
          successCount++;
          progress.value.current = i + 1;
        } catch (err) {
          errors.push(`${file.name}: ${err instanceof Error ? err.message : String(err)}`);
        }
      }

      progress.value.status = "Upload complete!";
      const expectedCount = initialCount + successCount;
      const deadline = Date.now() + 3000;
      await deps.reloadFiles();
      while (deps.files.value.length < expectedCount && Date.now() < deadline) {
        await new Promise((r) => setTimeout(r, 300));
        await deps.reloadFiles();
      }

      if (errors.length === 0) {
        success(`Successfully uploaded ${successCount} file(s)!`);
      } else if (successCount > 0) {
        warning(`Uploaded ${successCount} file(s), ${errors.length} failed: ${errors[0]}`);
      } else {
        error(`All uploads failed. ${errors[0]}`);
      }
    } finally {
      uploading.value = false;
      progress.value = idle();
    }
  }

  return { uploading, progress, uploadFiles };
}
