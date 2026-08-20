import { getApiUrl } from "../utils/api-config";

// Apple pins MapKit JS behind a "latest 5.x" URL, so the browser always gets the current
// patch release without us redeploying. Loading the full bundle (rather than mapkit.core.js
// plus data-libraries) keeps the setup to a single script tag; the map filter is not on the
// critical path of any page, since the script is only fetched when the user opens the map.
const MAPKIT_SRC = "https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js";

/**
 * The slice of the MapKit JS surface this app uses. Apple ships no types for the CDN bundle,
 * so this is hand-written and deliberately narrow — anything not declared here is a mistake
 * waiting to happen rather than a feature we forgot.
 */
export interface MapKitCoordinate {
  latitude: number;
  longitude: number;
}

export interface MapKitAnnotation {
  // Our own payload, carried through selection events: which files sit at this pin.
  data: { fileIds: number[] };
  // Present only on the cluster annotation MapKit synthesises for overlapping pins.
  memberAnnotations?: MapKitAnnotation[];
}

export interface MapKitCoordinateSpan {
  latitudeDelta: number;
  longitudeDelta: number;
}

/**
 * MapKit's viewport: where the map is centred and how much ground it covers. There is no integer
 * zoom in MapKit JS — the span is the zoom, and this is the only representation you can both read
 * back after a pan and write to restore one, which is why albums store it verbatim.
 */
export interface MapKitCoordinateRegion {
  center: MapKitCoordinate;
  span: MapKitCoordinateSpan;
}

export interface MapKitMap {
  region: MapKitCoordinateRegion;
  addAnnotations(annotations: MapKitAnnotation[]): void;
  removeAnnotations(annotations: MapKitAnnotation[]): void;
  showItems(items: MapKitAnnotation[], options?: { padding?: unknown }): void;
  addEventListener(type: string, listener: (event: { annotation: MapKitAnnotation }) => void): void;
  destroy(): void;
  annotationForCluster?: (cluster: MapKitAnnotation) => MapKitAnnotation | undefined;
}

export interface MapKit {
  init(options: { authorizationCallback: (done: (token: string) => void) => void }): void;
  Map: new (element: HTMLElement, options?: Record<string, unknown>) => MapKitMap;
  Coordinate: new (latitude: number, longitude: number) => MapKitCoordinate;
  CoordinateSpan: new (
    latitudeDelta: number,
    longitudeDelta: number,
  ) => MapKitCoordinateSpan;
  CoordinateRegion: new (
    center: MapKitCoordinate,
    span: MapKitCoordinateSpan,
  ) => MapKitCoordinateRegion;
  MarkerAnnotation: new (
    coordinate: MapKitCoordinate,
    options?: Record<string, unknown>,
  ) => MapKitAnnotation;
  Padding: new (options: {
    top: number;
    right: number;
    bottom: number;
    left: number;
  }) => unknown;
}

declare global {
  interface Window {
    mapkit?: MapKit;
  }
}

// Module-scoped: the script tag and mapkit.init() must happen exactly once per page, no matter
// how many gallery views mount a map. Every caller awaits the same promise.
let loader: Promise<MapKit> | null = null;

function loadScript(): Promise<void> {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${MAPKIT_SRC}"]`);
    if (existing) {
      if (window.mapkit) {
        resolve();
        return;
      }
      existing.addEventListener("load", () => resolve());
      existing.addEventListener("error", () => reject(new Error("MapKit JS failed to load")));
      return;
    }
    const script = document.createElement("script");
    script.src = MAPKIT_SRC;
    script.crossOrigin = "anonymous";
    script.async = true;
    script.addEventListener("load", () => resolve());
    script.addEventListener("error", () => reject(new Error("MapKit JS failed to load")));
    document.head.appendChild(script);
  });
}

/**
 * Loads MapKit JS and initialises it against our token endpoint.
 *
 * <p>The authorization callback is invoked by MapKit itself, both at init and again whenever the
 * token nears expiry, so it must stay able to fetch a fresh one for the life of the page — which
 * is why it re-fetches rather than closing over a cached string.
 *
 * @returns the initialised global `mapkit`, or a rejected promise if the script or the token
 *   could not be fetched (the caller shows the error instead of an empty grey box)
 */
export function ensureMapKit(): Promise<MapKit> {
  if (loader) return loader;

  loader = loadScript()
    .then(async () => {
      const mapkit = window.mapkit;
      if (!mapkit) {
        throw new Error("MapKit JS loaded but did not register itself");
      }
      // Fetch one token up front so a misconfigured server surfaces here, as a rejected promise
      // with a real message, rather than inside MapKit's callback where it is invisible.
      await fetchToken();
      mapkit.init({
        authorizationCallback: (done) => {
          fetchToken()
            .then(done)
            .catch((err) => console.error("MapKit token refresh failed:", err));
        },
      });
      return mapkit;
    })
    .catch((err) => {
      // Don't poison the cache: a later attempt (network back, server reconfigured) retries.
      loader = null;
      throw err;
    });

  return loader;
}

async function fetchToken(): Promise<string> {
  const response = await fetch(`${getApiUrl()}/api/maps/token`);
  if (!response.ok) {
    throw new Error(
      response.status === 503
        ? "Apple Maps is not configured on this server"
        : `Map token request failed (HTTP ${response.status})`,
    );
  }
  return (await response.text()).trim();
}
