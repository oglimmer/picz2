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
  playbackProgress: ComputedRef<number>;
  currentTime: ComputedRef<string>;
  totalTime: ComputedRef<string>;
  audioUrl: Ref<string | null>;
  loadRecordings: (
    albumId: number,
    filterTag?: string | null,
  ) => Promise<RecordingInfo[]>;
  hasRecordings: (filterTag: string) => boolean;
  getRecordingsCount: (filterTag: string) => number;
  startPlayback: (
    recording: RecordingInfo,
    files: AlbumFile[],
    audioElementRef: HTMLAudioElement,
  ) => Promise<void>;
  stopPlayback: () => void;
  pausePlayback: () => void;
  resumePlayback: () => void;
  deleteRecording: (recordingId: number) => Promise<boolean>;
  formatTime: (ms: number) => string;
}

/**
 * Slideshow playback composable
 * Handles playing back recorded slideshows with synchronized audio and images
 */
export function useSlideshowPlayback(): SlideshowPlaybackComposable {
  const { apiUrl, fetchWithAuth } = useApi();

  const isPlaying = ref<boolean>(false);
  const currentRecording = ref<RecordingInfo | null>(null);
  const currentImageIndex = ref<number>(0);
  const audioElement = ref<HTMLAudioElement | null>(null);
  const audioUrl = ref<string | null>(null);
  const playbackError = ref<string | null>(null);
  const recordings = ref<RecordingInfo[]>([]);
  const loadingRecordings = ref<boolean>(false);
  const playbackTimeline = ref<PlaybackTimelineEntry[]>([]);

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

      const response = await fetchWithAuth(url);

      if (!response.ok) {
        throw new Error("Failed to load recordings");
      }

      const data = await response.json();
      recordings.value = data.recordings || [];
      return recordings.value;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      console.error("Failed to load recordings:", err);
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

  /**
   * Get recordings count for a filter tag
   */
  function getRecordingsCount(filterTag: string): number {
    // Normalize empty string to null for comparison
    const normalizedTag = filterTag || null;
    return recordings.value.filter((r) => r.filterTag === normalizedTag).length;
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

      audioElement.value.addEventListener("timeupdate", handleTimeUpdate);
      audioElement.value.addEventListener("ended", handleEnded);
      audioElement.value.addEventListener("error", handleError);

      // Start playing
      await audioElement.value.play();
      isPlaying.value = true;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      console.error("Failed to start playback:", err);
      playbackError.value = "Failed to start playback: " + errorMessage;
      stopPlayback();
      throw err;
    }
  }

  /**
   * Stop playback
   */
  function stopPlayback(): void {
    if (audioElement.value) {
      audioElement.value.pause();
      audioElement.value.removeEventListener("timeupdate", () => {});
      audioElement.value.removeEventListener("ended", () => {});
      audioElement.value.removeEventListener("error", () => {});
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
   * Get playback progress (0-100)
   */
  const playbackProgress = computed<number>(() => {
    if (!audioElement.value || !currentRecording.value) return 0;

    const currentTime = audioElement.value.currentTime * 1000;
    const totalDuration = currentRecording.value.durationMs;

    return (currentTime / totalDuration) * 100;
  });

  /**
   * Delete a recording
   */
  async function deleteRecording(recordingId: number): Promise<boolean> {
    try {
      const response = await fetchWithAuth(
        `${apiUrl}/api/recordings/${recordingId}`,
        {
          method: "DELETE",
        },
      );

      if (!response.ok) {
        throw new Error("Failed to delete recording");
      }

      // Remove from local recordings array
      recordings.value = recordings.value.filter((r) => r.id !== recordingId);

      return true;
    } catch (err) {
      console.error("Failed to delete recording:", err);
      throw err;
    }
  }

  /**
   * Format milliseconds to MM:SS
   */
  function formatTime(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes}:${remainingSeconds.toString().padStart(2, "0")}`;
  }

  const currentTime = computed<string>(() => {
    if (!audioElement.value) return "0:00";
    return formatTime(audioElement.value.currentTime * 1000);
  });

  const totalTime = computed<string>(() => {
    if (!currentRecording.value) return "0:00";
    return formatTime(currentRecording.value.durationMs);
  });

  return {
    // State
    isPlaying,
    currentRecording,
    currentImageIndex,
    currentFile,
    playbackError,
    recordings,
    loadingRecordings,
    playbackProgress,
    currentTime,
    totalTime,
    audioUrl,

    // Methods
    loadRecordings,
    hasRecordings,
    getRecordingsCount,
    startPlayback,
    stopPlayback,
    pausePlayback,
    resumePlayback,
    deleteRecording,
    formatTime,
  };
}
