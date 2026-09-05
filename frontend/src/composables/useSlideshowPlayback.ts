import { ref, computed, type Ref, type ComputedRef } from "vue";
import { useApi } from "./useApi";
import type { AlbumFile, RecordingInfo, PlaybackTimelineEntry } from "@/types";

export interface SlideshowPlaybackComposable {
  isPlaying: Ref<boolean>;
  currentRecording: Ref<RecordingInfo | null>;
  currentImageIndex: Ref<number>;
  currentFile: ComputedRef<AlbumFile | null | undefined>;
  playbackError: Ref<string | null>;
  recordings: Ref<RecordingInfo[]>;
  loadingRecordings: Ref<boolean>;
  audioUrl: Ref<string | null>;
  loadRecordings: (
    albumId: number,
    filterTag?: string | null,
  ) => Promise<RecordingInfo[]>;
  hasRecordings: (filterTag: string) => boolean;
  recordingFor: (filterTag: string | null, language: string) => RecordingInfo | undefined;
  hasRecordingFor: (filterTag: string | null, language: string) => boolean;
  startPlayback: (
    recording: RecordingInfo,
    files: AlbumFile[],
    audioElementRef: HTMLAudioElement,
  ) => Promise<void>;
  stopPlayback: () => void;
  pausePlayback: () => void;
  resumePlayback: () => void;
  deleteRecording: (recordingId: number) => Promise<boolean>;
}

/**
 * Slideshow playback composable
 * Handles playing back recorded slideshows with synchronized audio and images
 */
export function useSlideshowPlayback(): SlideshowPlaybackComposable {
  const { apiUrl, requestJson } = useApi();

  const isPlaying = ref<boolean>(false);
  const currentRecording = ref<RecordingInfo | null>(null);
  const currentImageIndex = ref<number>(0);
  const audioElement = ref<HTMLAudioElement | null>(null);
  const audioUrl = ref<string | null>(null);
  const playbackError = ref<string | null>(null);
  const recordings = ref<RecordingInfo[]>([]);
  const loadingRecordings = ref<boolean>(false);
  const playbackTimeline = ref<PlaybackTimelineEntry[]>([]);
  // The handlers attached to the current audio element, kept so stopPlayback can detach the
  // very same functions. removeEventListener with a fresh arrow function removes nothing, and
  // the element is reused across plays, so without this every play stacked another set.
  let attached: {
    element: HTMLAudioElement;
    onTimeUpdate: () => void;
    onEnded: () => void;
    onError: (e: Event) => void;
  } | null = null;

  /**
   * Load recordings for a specific album and optional filter tag
   */
  async function loadRecordings(
    albumId: number,
    filterTag: string | null = null,
  ): Promise<RecordingInfo[]> {
    try {
      loadingRecordings.value = true;
      playbackError.value = null;

      let url = `${apiUrl}/api/albums/${albumId}/recordings`;
      if (filterTag) {
        url += `?filterTag=${encodeURIComponent(filterTag)}`;
      }

      const data = await requestJson<{ recordings?: RecordingInfo[] }>(url);
      recordings.value = data.recordings || [];
      return recordings.value;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      playbackError.value = "Failed to load recordings: " + errorMessage;
      recordings.value = [];
      return [];
    } finally {
      loadingRecordings.value = false;
    }
  }

  /**
   * Check if a filter tag has recordings
   */
  function hasRecordings(filterTag: string): boolean {
    // Normalize empty string to null for comparison
    const normalizedTag = filterTag || null;
    return recordings.value.some((r) => r.filterTag === normalizedTag);
  }

  /** The recording for this tag filter ("" or null means the whole album) in this language. */
  function recordingFor(filterTag: string | null, language: string): RecordingInfo | undefined {
    const normalizedTag = filterTag || null;
    return recordings.value.find((r) => r.filterTag === normalizedTag && r.language === language);
  }

  function hasRecordingFor(filterTag: string | null, language: string): boolean {
    return recordingFor(filterTag, language) !== undefined;
  }

  /**
   * Start playback of a recording
   */
  async function startPlayback(
    recording: RecordingInfo,
    files: AlbumFile[],
    audioElementRef: HTMLAudioElement,
  ): Promise<void> {
    try {
      playbackError.value = null;
      currentRecording.value = recording;
      currentImageIndex.value = 0;
      audioElement.value = audioElementRef;

      // Set audio source using public token for unauthenticated access
      audioUrl.value = `${apiUrl}/api/r/${recording.publicToken}/audio`;

      // Setup playback timeline
      playbackTimeline.value = recording.images.map((img) => {
        const file = files.find((f) => f.id === img.fileId);
        return {
          ...img,
          file,
        };
      });

      // Wait for audio element to be ready
      if (!audioElement.value) {
        throw new Error("Audio element not available");
      }

      // Set the source
      audioElement.value.src = audioUrl.value;

      // Track current image based on playback time
      const handleTimeUpdate = () => {
        if (!audioElement.value) return;
        const currentTimeMs = audioElement.value.currentTime * 1000;

        // Find which image should be showing
        for (let i = playbackTimeline.value.length - 1; i >= 0; i--) {
          if (currentTimeMs >= playbackTimeline.value[i].startTimeMs) {
            if (currentImageIndex.value !== i) {
              currentImageIndex.value = i;
            }
            break;
          }
        }
      };

      // Handle playback end
      const handleEnded = () => {
        stopPlayback();
      };

      // Handle errors
      const handleError = (e: Event) => {
        console.error("Audio playback error:", e);
        playbackError.value = "Failed to play audio";
        stopPlayback();
      };

      detachListeners();
      audioElement.value.addEventListener("timeupdate", handleTimeUpdate);
      audioElement.value.addEventListener("ended", handleEnded);
      audioElement.value.addEventListener("error", handleError);
      attached = {
        element: audioElement.value,
        onTimeUpdate: handleTimeUpdate,
        onEnded: handleEnded,
        onError: handleError,
      };

      // Start playing
      await audioElement.value.play();
      isPlaying.value = true;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      playbackError.value = "Failed to start playback: " + errorMessage;
      stopPlayback();
      throw err;
    }
  }

  function detachListeners(): void {
    if (!attached) return;
    const { element, onTimeUpdate, onEnded, onError } = attached;
    element.removeEventListener("timeupdate", onTimeUpdate);
    element.removeEventListener("ended", onEnded);
    element.removeEventListener("error", onError);
    attached = null;
  }

  /**
   * Stop playback
   */
  function stopPlayback(): void {
    detachListeners();
    if (audioElement.value) {
      audioElement.value.pause();
      audioElement.value.src = "";
    }

    audioElement.value = null;
    audioUrl.value = null;
    isPlaying.value = false;
    currentImageIndex.value = 0;
    playbackTimeline.value = [];
    currentRecording.value = null;
  }

  /**
   * Pause playback
   */
  function pausePlayback(): void {
    if (audioElement.value) {
      audioElement.value.pause();
    }
  }

  /**
   * Resume playback
   */
  function resumePlayback(): void {
    if (audioElement.value) {
      audioElement.value.play();
    }
  }

  /**
   * Get the current file being displayed
   */
  const currentFile = computed<AlbumFile | null | undefined>(() => {
    if (!playbackTimeline.value || currentImageIndex.value < 0) {
      return null;
    }

    const timelineEntry = playbackTimeline.value[currentImageIndex.value];
    if (!timelineEntry) return null;

    return timelineEntry.file;
  });

  /**
   * Delete a recording
   */
  async function deleteRecording(recordingId: number): Promise<boolean> {
    await requestJson(`${apiUrl}/api/recordings/${recordingId}`, { method: "DELETE" });
    recordings.value = recordings.value.filter((r) => r.id !== recordingId);
    return true;
  }

  return {
    // State
    isPlaying,
    currentRecording,
    currentImageIndex,
    currentFile,
    playbackError,
    recordings,
    loadingRecordings,
    audioUrl,

    // Methods
    loadRecordings,
    hasRecordings,
    recordingFor,
    hasRecordingFor,
    startPlayback,
    stopPlayback,
    pausePlayback,
    resumePlayback,
    deleteRecording,
  };
}
