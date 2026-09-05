import { describe, expect, it } from "vitest";
import {
  fileLatLng,
  formatCoordinates,
  formatDistance,
  groupByDayAndRegion,
  haversineMeters,
} from "../dayRegionGrouping";
import type { AlbumFile } from "@/types";

let nextId = 1;
function photo(
  overrides: Partial<AlbumFile> & { at?: [number, number]; taken?: string },
): AlbumFile {
  const { at, taken, ...rest } = overrides;
  return {
    id: nextId++,
    albumId: 1,
    filename: "x.jpg",
    path: "",
    size: 1,
    uploadedAt: "2026-05-04T12:00:00Z",
    exifDateTimeOriginal: taken,
    gpsLatitude: at?.[0],
    gpsLongitude: at?.[1],
    tags: [],
    ...rest,
  } as AlbumFile;
}

const MUNICH: [number, number] = [48.137, 11.575];
const TORONTO: [number, number] = [43.65, -79.38];

describe("haversineMeters", () => {
  it("is zero for the same point and symmetric", () => {
    const a = { lat: 48.1, lng: 11.5 };
    const b = { lat: 48.2, lng: 11.6 };
    expect(haversineMeters(a, a)).toBe(0);
    expect(haversineMeters(a, b)).toBeCloseTo(haversineMeters(b, a), 6);
  });

  it("knows how far Munich is from Toronto (about 6 600 km)", () => {
    const km =
      haversineMeters({ lat: MUNICH[0], lng: MUNICH[1] }, { lat: TORONTO[0], lng: TORONTO[1] }) /
      1000;
    expect(km).toBeGreaterThan(6500);
    expect(km).toBeLessThan(6700);
  });
});

describe("groupByDayAndRegion", () => {
  it("cuts days on the camera's clock, not the viewer's", () => {
    // 19:00 in Toronto on 4 May is 23:00 UTC; a European viewer would file it under 5 May.
    const evening = photo({
      taken: "2026-05-04T23:00:00Z",
      captureUtcOffsetSeconds: -4 * 3600,
      at: TORONTO,
    });
    const [day] = groupByDayAndRegion([evening]);
    expect(day.key).toBe("2026-05-04");
  });

  it("gives an offset-less photo the album's dominant offset", () => {
    const withOffset = photo({ taken: "2026-05-04T23:00:00Z", captureUtcOffsetSeconds: -4 * 3600 });
    const without = photo({ taken: "2026-05-04T23:30:00Z" });
    const days = groupByDayAndRegion([withOffset, without]);
    expect(days).toHaveLength(1);
    expect(days[0].key).toBe("2026-05-04");
    expect(days[0].count).toBe(2);
  });

  it("keeps clusters no wider than the radius and does not chain across a city", () => {
    // Three photos 1.5 km apart in a line: A–B and B–C are each within a 2 km radius, but A–C is
    // 3 km. Complete linkage must refuse to merge all three into one 3 km "region".
    const base = 48.137;
    const step = 1500 / 111_000; // ~1.5 km in latitude degrees
    const a = photo({ taken: "2026-05-04T10:00:00Z", at: [base, 11.575] });
    const b = photo({ taken: "2026-05-04T10:10:00Z", at: [base + step, 11.575] });
    const c = photo({ taken: "2026-05-04T10:20:00Z", at: [base + 2 * step, 11.575] });
    const [day] = groupByDayAndRegion([a, b, c], 2000);
    const sizes = day.clusters.map((cl) => cl.files.length).sort();
    expect(sizes).toEqual([1, 2]);
    for (const cluster of day.clusters) {
      expect(cluster.spreadMeters).toBeLessThanOrEqual(2000);
    }
  });

  it("keeps album order inside and across clusters and parks the unlocated photos last", () => {
    const first = photo({ taken: "2026-05-04T10:00:00Z", at: MUNICH });
    const noGps = photo({ taken: "2026-05-04T10:05:00Z" });
    const second = photo({ taken: "2026-05-04T10:10:00Z", at: MUNICH });
    const [day] = groupByDayAndRegion([first, noGps, second]);
    expect(day.clusters.map((c) => c.located)).toEqual([true, false]);
    expect(day.clusters[0].files.map((f) => f.id)).toEqual([first.id, second.id]);
    expect(day.clusters[1].files).toEqual([noGps]);
    expect(day.clusters[1].center).toBeNull();
  });

  it("puts photos with no usable date in a trailing 'unknown' day", () => {
    const dated = photo({ taken: "2026-05-04T10:00:00Z" });
    const undated = photo({ taken: "not a date", uploadedAt: "" });
    const days = groupByDayAndRegion([dated, undated]);
    expect(days.map((d) => d.key)).toEqual(["2026-05-04", "unknown"]);
    expect(days[1].date).toBeNull();
  });
});

describe("labels", () => {
  it("formats distances and coordinates for headings", () => {
    expect(formatDistance(0)).toBe("0 m");
    expect(formatDistance(834)).toBe("830 m");
    expect(formatDistance(1234)).toBe("1.2 km");
    expect(formatCoordinates({ lat: 48.13712, lng: 11.5756 })).toBe("48.137, 11.576");
  });

  it("reads a position only when both coordinates are real numbers", () => {
    expect(fileLatLng(photo({ at: MUNICH }))).toEqual({ lat: MUNICH[0], lng: MUNICH[1] });
    expect(fileLatLng(photo({}))).toBeNull();
    expect(fileLatLng(photo({ gpsLatitude: NaN, gpsLongitude: 1 }))).toBeNull();
  });
});
