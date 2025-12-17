import { ref, computed, type Ref, type ComputedRef } from "vue";
import { useAudioRecorder } from "./useAudioRecorder";
import { useApi } from "./useApi";
import type { AlbumFile, ImageTimingEntry } from "@/types";

export interface SlideshowComposable {
  isRecording: Ref<boolean>;
  isInRecordingMode: Ref<boolean>;
  uploading: Ref<boolean>;
  uploadError: Ref<string | null>;
  recorderError: Ref<string | null>;
  audioBlob: Ref<Blob | null>;
  imageTimings: Ref<ImageTimingEntry[]>;
  totalDuration: ComputedRef<number>;
  startRecording: (
    albumIdValue: number,
    filterTagValue: string | null,
    languageValue: string,
    firstFile: AlbumFile | null,
  ) => Promise<void>;
  stopRecordingAndUpload: () => Promise<unknown>;
  trackImageStart: (file: AlbumFile) => void;
  cancelRecording: () => void;
  reset: () => void;
}

/**
 * Slideshow recording composable
 * Manages recording state, image timing, and upload
 */
export function useSlideshow(): SlideshowComposable {
  const { apiUrl, fetchWithAuth } = useApi();
  const {
    isRecording,
    audioBlob,
    error: recorderError,
    startRecording: startAudioRecording,
    stopRecording: stopAudioRecording,
    reset: resetRecorder,
  } = useAudioRecorder();

  const isInRecordingMode = ref<boolean>(false);
  const recordingStartTime = ref<number | null>(null);
  const currentImageStartTime = ref<number | null>(null);
  const imageTimings = ref<ImageTimingEntry[]>([]);
  const filterTag = ref<string | null>(null);
  const language = ref<string | null>(null);
  const albumId = ref<number | null>(null);
  const uploading = ref<boolean>(false);
  const uploadError = ref<string | null>(null);

  const totalDuration = computed<number>(() => {
    if (!recordingStartTime.value) return 0;
    const now = Date.now();
    return now - recordingStartTime.value;
  });

  /**
   * Start slideshow recording mode
   */
  async function startRecording(
    albumIdValue: number,
    filterTagValue: string | null,
    languageValue: string,
    firstFile: AlbumFile | null,
  ): Promise<void> {
    try {
      // Reset state
      imageTimings.value = [];
      uploadError.value = null;
      albumId.value = albumIdValue;
      filterTag.value = filterTagValue;
      language.value = languageValue;

      // Start audio recording
      await startAudioRecording();

      // Set recording mode
      isInRecordingMode.value = true;
      recordingStartTime.value = Date.now();
      currentImageStartTime.value = Date.now();

      // Track first image
      if (firstFile) {
        trackImageStart(firstFile);
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      console.error("Failed to start recording:", err);
      uploadError.value = "Failed to start recording: " + errorMessage;
      isInRecordingMode.value = false;
      throw err;
    }
  }

  /**
   * Track when a new image is shown
   */
  function trackImageStart(file: AlbumFile): void {
    const now = Date.now();

    // If there was a previous image, save its duration
    if (imageTimings.value.length > 0) {
      const lastTiming = imageTimings.value[imageTimings.value.length - 1];
      if (!lastTiming.durationMs && currentImageStartTime.value) {
        lastTiming.durationMs = now - currentImageStartTime.value;
      }
    }

    // Add new image timing
    imageTimings.value.push({
      fileId: file.id,
      startTimeMs: recordingStartTime.value
        ? now - recordingStartTime.value
        : 0,
      durationMs: null, // Will be set when next image starts or recording stops
    });

    currentImageStartTime.value = now;
  }

  /**
   * Stop recording and upload to server
   */
  async function stopRecordingAndUpload(): Promise<unknown> {
    try {
      uploading.value = true;
      uploadError.value = null;

      // Stop audio recording
      const audioData = await stopAudioRecording();

      // Calculate final image duration
      const now = Date.now();
      if (imageTimings.value.length > 0) {
        const lastTiming = imageTimings.value[imageTimings.value.length - 1];
        if (!lastTiming.durationMs && currentImageStartTime.value) {
          lastTiming.durationMs = now - currentImageStartTime.value;
        }
      }

      const totalDurationMs = recordingStartTime.value
        ? now - recordingStartTime.value
        : 0;

      // Prepare upload data
      const formData = new FormData();

      // Add audio file
      const audioFile = new File([audioData], "recording.webm", {
        type: audioData.type,
      });
      formData.append("audio", audioFile);

      // Add recording data as JSON
      const recordingData = {
        filterTag: filterTag.value,
        language: language.value,
        durationMs: totalDurationMs,
        images: imageTimings.value.map((timing) => ({
          fileId: timing.fileId,
          startTimeMs: timing.startTimeMs,
          durationMs: timing.durationMs,
        })),
      };
      formData.append("data", JSON.stringify(recordingData));

      // Upload to server
      const response = await fetchWithAuth(
        `${apiUrl}/api/albums/${albumId.value}/recordings`,
        {
          method: "POST",
          body: formData,
        },
      );

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.message || "Upload failed");
      }

      const result = await response.json();

      // Reset state
      reset();

      return result;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      console.error("Failed to upload recording:", err);
      uploadError.value = "Failed to upload recording: " + errorMessage;
      throw err;
    } finally {
      uploading.value = false;
    }
  }

  /**
   * Cancel recording without saving
   */
  function cancelRecording(): void {
    resetRecorder();
    reset();
  }

  /**
   * Reset all state
   */
  function reset(): void {
    isInRecordingMode.value = false;
    recordingStartTime.value = null;
    currentImageStartTime.value = null;
    imageTimings.value = [];
    filterTag.value = null;
    language.value = null;
    albumId.value = null;
    uploading.value = false;
    resetRecorder();
  }

  return {
    // State
    isRecording,
    isInRecordingMode,
    uploading,
    uploadError,
    recorderError,
    audioBlob,
    imageTimings,
    totalDuration,

    // Methods
    startRecording,
    stopRecordingAndUpload,
    trackImageStart,
    cancelRecording,
    reset,
  };
}
