import { ref, type Ref } from "vue";

export interface AudioRecorderComposable {
  isRecording: Ref<boolean>;
  audioBlob: Ref<Blob | null>;
  error: Ref<string | null>;
  startRecording: () => Promise<void>;
  stopRecording: () => Promise<Blob>;
  cancelRecording: () => void;
  reset: () => void;
}

/**
 * Audio recording composable using MediaRecorder API
 */
export function useAudioRecorder(): AudioRecorderComposable {
  const isRecording = ref<boolean>(false);
  const audioBlob = ref<Blob | null>(null);
  const mediaRecorder = ref<MediaRecorder | null>(null);
  const audioChunks = ref<Blob[]>([]);
  const error = ref<string | null>(null);

  /**
   * Start recording audio
   */
  async function startRecording(): Promise<void> {
    try {
      error.value = null;
      audioBlob.value = null;
      audioChunks.value = [];

      // Request microphone permission
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

      // Create MediaRecorder
      const options: MediaRecorderOptions = { mimeType: "audio/webm" };

      // Try to use opus codec if available
      if (MediaRecorder.isTypeSupported("audio/webm;codecs=opus")) {
        options.mimeType = "audio/webm;codecs=opus";
      } else if (MediaRecorder.isTypeSupported("audio/ogg;codecs=opus")) {
        options.mimeType = "audio/ogg;codecs=opus";
      }

      mediaRecorder.value = new MediaRecorder(stream, options);

      // Collect audio data
      mediaRecorder.value.ondataavailable = (event: BlobEvent) => {
        if (event.data.size > 0) {
          audioChunks.value.push(event.data);
        }
      };

      // Handle recording stop
      mediaRecorder.value.onstop = () => {
        const mimeType = mediaRecorder.value!.mimeType;
        audioBlob.value = new Blob(audioChunks.value, { type: mimeType });

        // Stop all tracks to release microphone
        stream.getTracks().forEach((track) => track.stop());

        isRecording.value = false;
      };

      // Handle errors
      mediaRecorder.value.onerror = (event: Event) => {
        const errorEvent = event as ErrorEvent;
        error.value = "Recording error: " + errorEvent.error;
        console.error("MediaRecorder error:", errorEvent.error);
        isRecording.value = false;
      };

      // Start recording
      mediaRecorder.value.start();
      isRecording.value = true;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      error.value = "Failed to start recording: " + errorMessage;
      console.error("Error starting recording:", err);
      isRecording.value = false;
      throw err;
    }
  }

  /**
   * Stop recording audio
   */
  async function stopRecording(): Promise<Blob> {
    return new Promise((resolve, reject) => {
      if (!mediaRecorder.value || mediaRecorder.value.state === "inactive") {
        reject(new Error("No active recording"));
        return;
      }

      // Listen for the stop event to get the final blob
      const handleStop = () => {
        mediaRecorder.value!.removeEventListener("stop", handleStop);
        if (audioBlob.value) {
          resolve(audioBlob.value);
        } else {
          reject(new Error("Failed to create audio blob"));
        }
      };

      mediaRecorder.value.addEventListener("stop", handleStop);
      mediaRecorder.value.stop();
    });
  }

  /**
   * Cancel recording without saving
   */
  function cancelRecording(): void {
    if (mediaRecorder.value && mediaRecorder.value.state !== "inactive") {
      mediaRecorder.value.stop();
    }

    audioBlob.value = null;
    audioChunks.value = [];
    isRecording.value = false;
  }

  /**
   * Reset the recorder state
   */
  function reset(): void {
    cancelRecording();
    error.value = null;
  }

  return {
    isRecording,
    audioBlob,
    error,
    startRecording,
    stopRecording,
    cancelRecording,
    reset,
  };
}
