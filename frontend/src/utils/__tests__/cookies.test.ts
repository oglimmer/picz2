import { beforeEach, describe, expect, it } from "vitest";
import { readCookie, writeCookie } from "../cookies";

describe("cookies", () => {
  beforeEach(() => {
    for (const name of ["a", "b", "cookie_consent"]) writeCookie(name, "", -1);
  });

  it("reads back what it wrote, and null for a cookie that is not there", () => {
    writeCookie("cookie_consent", "accepted", 30);
    writeCookie("b", "x=y", 30);
    expect(readCookie("cookie_consent")).toBe("accepted");
    // A value containing "=" survives: only the first "=" separates name from value.
    expect(readCookie("b")).toBe("x=y");
    expect(readCookie("nope")).toBeNull();
  });

  it("expires a cookie when asked", () => {
    writeCookie("a", "1", 30);
    expect(readCookie("a")).toBe("1");
    writeCookie("a", "", -1);
    expect(readCookie("a")).toBeNull();
  });
});
