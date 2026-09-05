import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { formatBytes, formatDate, isVideo } from "../format";

describe("formatBytes", () => {
  it("scales through the units and clamps at PB", () => {
    expect(formatBytes(0)).toBe("0 Bytes");
    expect(formatBytes(512)).toBe("512 Bytes");
    expect(formatBytes(1536)).toBe("1.5 KB");
    expect(formatBytes(5 * 1024 ** 3)).toBe("5 GB");
    expect(formatBytes(1024 ** 5)).toBe("1 PB");
    // Past the table: still readable, never "undefined".
    expect(formatBytes(1024 ** 6)).toBe("1024 PB");
  });

  it("treats garbage as nothing", () => {
    expect(formatBytes(NaN)).toBe("0 Bytes");
    expect(formatBytes(-3)).toBe("0 Bytes");
  });
});

describe("formatDate", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    // A Wednesday, mid-afternoon local time.
    vi.setSystemTime(new Date(2026, 8, 9, 15, 0, 0));
  });
  afterEach(() => vi.useRealTimers());

  const at = (dayOffset: number, hour: number) =>
    new Date(2026, 8, 9 + dayOffset, hour, 0, 0).toISOString();

  it("counts calendar days, not 24-hour blocks", () => {
    expect(formatDate(at(0, 0))).toBe("Today");
    // 23:50 yesterday is yesterday even though it is under 24 h ago.
    expect(formatDate(new Date(2026, 8, 8, 23, 50).toISOString())).toBe("Yesterday");
    expect(formatDate(at(-3, 12))).toBe("3 days ago");
    expect(formatDate(at(-6, 12))).toBe("6 days ago");
  });

  it("falls back to the plain date at a week and for the future", () => {
    const week = new Date(2026, 8, 2, 12);
    expect(formatDate(week.toISOString())).toBe(week.toLocaleDateString());
    // A camera with a wrong clock must not read as "Today".
    const future = new Date(2026, 8, 11, 12);
    expect(formatDate(future.toISOString())).toBe(future.toLocaleDateString());
  });

  it("renders nothing for an unparseable timestamp", () => {
    expect(formatDate("nope")).toBe("");
  });
});

describe("isVideo", () => {
  it("looks at the wire field `mimetype` only", () => {
    expect(isVideo({ mimetype: "video/mp4" })).toBe(true);
    expect(isVideo({ mimetype: "image/jpeg" })).toBe(false);
    expect(isVideo({})).toBe(false);
  });
});
