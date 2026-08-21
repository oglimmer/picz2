/**
 * A saved map viewport — MapKit's CoordinateRegion, centre plus a span in degrees. The span is the
 * zoom: smaller shows less ground. Stored per album so the map filter opens where the owner framed
 * it instead of auto-fitting every pin.
 */
export interface MapView {
  centerLat: number;
  centerLng: number;
  spanLat: number;
  spanLng: number;
}

export interface Album {
  id: number;
  name: string;
  description?: string;
  fileCount?: number;
  coverFileId?: number;
  coverImageToken?: string;
  shareToken?: string;
  // Flat on the wire (see AlbumInfo on the server); all four present or all four absent.
  mapCenterLat?: number | null;
  mapCenterLng?: number | null;
  mapSpanLat?: number | null;
  mapSpanLng?: number | null;
}

/** Reads an album's saved view, or null when it has none (any missing field disqualifies it). */
export function albumMapView(album: Album | null | undefined): MapView | null {
  if (
    !album ||
    typeof album.mapCenterLat !== "number" ||
    typeof album.mapCenterLng !== "number" ||
    typeof album.mapSpanLat !== "number" ||
    typeof album.mapSpanLng !== "number"
  ) {
    return null;
  }
  return {
    centerLat: album.mapCenterLat,
    centerLng: album.mapCenterLng,
    spanLat: album.mapSpanLat,
    spanLng: album.mapSpanLng,
  };
}

export type ProcessingStatus =
  | "QUEUED"
  | "PROCESSING"
  | "DONE"
  | "FAILED"
  | "DEAD_LETTER";

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
  processingStatus?: ProcessingStatus;
  // False once the original has been purged by the retention CronJob (Phase 6 / Gap 4-finish).
  // Derivatives (thumb/medium/large/transcoded) keep serving; rotation/download-original do not.
  originalAvailable?: boolean;
  // Capture location in signed decimal degrees (WGS 84), absent when the file carries none.
  // Same reference frame MapKit JS expects, so these go straight into an annotation.
  gpsLatitude?: number | null;
  gpsLongitude?: number | null;
}

export interface Tag {
  id: number;
  name: string;
  albumId: number;
}

// Presentation image group — a per-(album, tag) section marker anchored to one image.
// The group owns that image and every following one until the next group starts.
export interface PresentationGroup {
  id: number;
  albumId: number;
  tag: string;
  startFileId: number;
  label: string;
  text?: string | null;
  createdAt?: string;
  updatedAt?: string;
}

// One rendered block of the presentation grid. `group` is null for images that come
// before the first group marker.
export interface PresentationSection {
  group: PresentationGroup | null;
  files: AlbumFile[];
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

// Phase 5 — server-advertised ingest paths. Mirrors the Spring CapabilitiesController record.
// `tus.enabled` here is the *advertised* flag (server-side R1 ships false, R2 flips true);
// the actual TUS endpoint at /files/ is always live when tusd is deployed.
export interface Capabilities {
  tus: TusCapability;
  multipart: MultipartCapability;
  maps: MapsCapability;
}

// Whether the server can mint MapKit JS tokens. False when maps.apple.* is unset, in which
// case the gallery hides the map filter instead of offering a map that would never load.
export interface MapsCapability {
  enabled: boolean;
  /**
   * Whether the server can turn coordinates into place names (`/api/geocode/reverse`). Needs the
   * same Apple credentials plus `maps.geocode.enabled`; false means region headings stay as
   * coordinates and the UI never calls the endpoint.
   */
  geocoding: boolean;
}

export interface TusCapability {
  enabled: boolean;
  endpoint: string;
  version: string;
  maxSize: number;
}

export interface MultipartCapability {
  enabled: boolean;
  endpoint: string;
}
