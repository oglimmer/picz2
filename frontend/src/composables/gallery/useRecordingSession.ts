import { computed, ref, type ComputedRef, type Ref } from "vue";
import { useConfirm } from "../useConfirm";
import { useNotifications } from "../useNotifications";
import { useSlideshow } from "../useSlideshow";
import type { Album, AlbumFile, RecordingInfo } from "@/types";

export type Language = "language1" | "language2";

export interface RecordingSessionDeps {
  album: Ref<Album | null>;
  files: Ref<AlbumFile[]>;
  selectedTag: Ref<string>;
  selectedFile: Ref<AlbumFile | null>;
  language1Name: Ref<string>;
  language2Name: Ref<string>;
  loadRecordings: (albumId: number) => Promise<unknown>;
  recordingFor: (tag: string | null, language: string) => RecordingInfo | undefined;
  deleteRecording: (recordingId: number) => Promise<boolean>;
}

export interface RecordingSession {
  selectedLanguage: Ref<Language>;
  isInRecordingMode: Ref<boolean>;
  savingRecording: Ref<boolean>;
  formattedDuration: ComputedRef<string>;
  start: () => Promise<void>;
  /** Called on a lightbox close: saves the recording first. Returns false to keep the lightbox open. */
  finishOnClose: () => Promise<boolean>;
  trackImage: (file: AlbumFile) => void;
  remove: (language: Language) => Promise<void>;
}

/**
 * Recording a narrated slideshow from the owner's presentation view: start on the first photo,
 * time every photo the lightbox moves to, and save when the lightbox closes.
 */
export function useRecordingSession(deps: RecordingSessionDeps): RecordingSession {
  const { success, warning, error } = useNotifications();
  const { confirm } = useConfirm();
  const {
    isInRecordingMode,
    totalDuration,
    startRecording,
    stopRecordingAndUpload,
    trackImageStart,
    cancelRecording,
  } = useSlideshow();

  const selectedLanguage = ref<Language>("language1");
  const savingRecording = ref(false);

  const formattedDuration = computed(() => {
    const seconds = Math.floor(totalDuration.value / 1000);
    const minutes = Math.floor(seconds / 60);
    return `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
  });

  async function start(): Promise<void> {
    if (!deps.album.value) return;
    if (deps.files.value.length === 0) {
      warning("No images available to start recording");
      return;
    }
    try {
      const firstFile = deps.files.value[0];
      await startRecording(
        deps.album.value.id,
        deps.selectedTag.value || null,
        selectedLanguage.value,
        firstFile,
      );
      deps.selectedFile.value = firstFile;
    } catch (err) {
      error("Failed to start recording: " + (err instanceof Error ? err.message : "Unknown error"));
    }
  }

  /**
   * The save keeps the lightbox mounted until the upload resolves, so every further close gesture
   * (backdrop click, repeated Escape) re-enters here. Those are swallowed instead of stacking a
   * second save, a second reload and a second toast on top of the first.
   */
  async function finishOnClose(): Promise<boolean> {
    if (savingRecording.value) return false;
    if (!isInRecordingMode.value) return true;

    savingRecording.value = true;
    try {
      await stopRecordingAndUpload();
      if (deps.album.value) await deps.loadRecordings(deps.album.value.id);
      success("Recording saved successfully!");
      return true;
    } catch {
      const discard = await confirm("Failed to save recording. Do you want to discard it?", {
        type: "warning",
        confirmText: "Discard",
      });
      if (discard) {
        cancelRecording();
        return true;
      }
      return false; // keep the lightbox open so the user can try again
    } finally {
      savingRecording.value = false;
    }
  }

  function trackImage(file: AlbumFile): void {
    if (isInRecordingMode.value) trackImageStart(file);
  }

  async function remove(language: Language): Promise<void> {
    const recording = deps.recordingFor(deps.selectedTag.value || null, language);
    if (!recording) return;

    const languageName =
      language === "language1" ? deps.language1Name.value : deps.language2Name.value;
    const filterDescription = deps.selectedTag.value ? `"${deps.selectedTag.value}"` : "all images";
    const confirmed = await confirm(
      `Delete the ${languageName} recording for ${filterDescription}? This action cannot be undone.`,
      { type: "danger", confirmText: "Delete" },
    );
    if (!confirmed) return;

    try {
      await deps.deleteRecording(recording.id);
      if (deps.album.value) await deps.loadRecordings(deps.album.value.id);
      success("Recording deleted successfully!");
    } catch (err) {
      error("Failed to delete recording: " + (err instanceof Error ? err.message : "Unknown error"));
    }
  }

  return {
    selectedLanguage,
    isInRecordingMode,
    savingRecording,
    formattedDuration,
    start,
    finishOnClose,
    trackImage,
    remove,
  };
}
