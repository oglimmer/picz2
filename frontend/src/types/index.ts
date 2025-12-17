export interface Album {
  id: number;
  name: string;
  description?: string;
  fileCount?: number;
  coverFileId?: number;
  coverImageToken?: string;
  shareToken?: string;
}

export interface AlbumFile {
  id: number;
  albumId: number;
  filename: string;
  originalName?: string;
  path: string;
  size: number;
  mimeType?: string;
  mimetype?: string;
  uploadedAt: string;
  exifDateTimeOriginal?: string;
  rotation?: number;
  tags: string[];
  order?: number;
  publicToken?: string;
}

export interface Tag {
  id: number;
  name: string;
  albumId: number;
}

export interface ImageTiming {
  imageId: number;
  startTime: number;
}

export interface SlideshowRecording {
  albumId: number;
  language: string;
  audioBlob: Blob;
  imageTimes: ImageTiming[];
}

export interface Language {
  code: string;
  name: string;
}

export interface AlbumSettings {
  languages?: Language[];
}

export interface AuthState {
  authEmail: string;
  authPassword: string;
  isLoggedIn: boolean;
  loginError: string;
}

export interface ApiResponse<T = unknown> {
  data?: T;
  error?: string;
  message?: string;
}

export type PresentationMode = "all" | "tagged" | "untagged";

export interface FileFilters {
  selectedTag: string | null;
  presentationMode: PresentationMode;
}

export interface TagCount {
  name: string;
  count: number;
}

export interface ImageTimingEntry {
  fileId: number;
  startTimeMs: number;
  durationMs: number | null;
}

export interface RecordingInfo {
  id: number;
  albumId: number;
  filterTag: string | null;
  language: string;
  durationMs: number;
  audioPath: string;
  publicToken: string;
  createdAt: string;
  images: ImageTimingEntry[];
}

export interface PlaybackTimelineEntry extends ImageTimingEntry {
  file?: AlbumFile;
}
