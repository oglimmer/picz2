import { ref, watch, type Ref } from "vue";
import { useNotifications } from "./useNotifications";
import { useSlideshowPlayback, type SlideshowPlaybackComposable } from "./useSlideshowPlayback";
import type { AlbumFile, RecordingInfo } from "@/types";

export interface PlaybackControls {
  playback: SlideshowPlaybackComposable;
  isPaused: Ref<boolean>;
  controlsVisible: Ref<boolean>;
  startPlayback: (tag: string, language: string) => Promise<void>;
  pauseResume: () => void;
  stop: () => void;
}

/**
 * Playing a recorded slideshow from either gallery: the audio element, the pause/stop state the
 * lightbox binds to, and the "which recording for this tag and language" lookup. The lightbox is
 * driven by moving `selectedFile` along with the recording's timeline.
 *
 * @param audioPlayer the view's `<audio>` template ref
 * @param beforeStart runs before the audio starts — the public page logs an analytics event here
 */
export function usePlaybackControls(
  files: Ref<AlbumFile[]>,
  selectedFile: Ref<AlbumFile | null>,
  audioPlayer: Ref<HTMLAudioElement | null>,
  beforeStart?: (recording: RecordingInfo, tag: string) => Promise<void>,
): PlaybackControls {
  const playback = useSlideshowPlayback();
  const { warning, error } = useNotifications();

  const isPaused = ref(false);
  const controlsVisible = ref(true);

  // Follow the recording: whichever photo the timeline says is current goes into the lightbox.
  watch(playback.currentFile, (file) => {
    if (playback.isPlaying.value && file) selectedFile.value = file;
  });

  async function startPlayback(tag: string, language: string): Promise<void> {
    if (files.value.length === 0) {
      warning("No images available to play");
      return;
    }
    const recording = playback.recordingFor(tag || null, language);
    if (!recording) {
      warning("No recording found for this filter and language");
      return;
    }
    if (!audioPlayer.value) {
      error("Audio player is not ready");
      return;
    }
    try {
      await beforeStart?.(recording, tag);
      await playback.startPlayback(recording, files.value, audioPlayer.value);
      isPaused.value = false;
      controlsVisible.value = true;
      if (playback.currentFile.value) selectedFile.value = playback.currentFile.value;
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      error("Failed to start playback: " + message);
    }
  }

  function pauseResume(): void {
    if (isPaused.value) {
      playback.resumePlayback();
    } else {
      playback.pausePlayback();
    }
    isPaused.value = !isPaused.value;
  }

  /** Stops the audio and closes the lightbox. */
  function stop(): void {
    playback.stopPlayback();
    isPaused.value = false;
    controlsVisible.value = true;
    selectedFile.value = null;
  }

  return { playback, isPaused, controlsVisible, startPlayback, pauseResume, stop };
}
