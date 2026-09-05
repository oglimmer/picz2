/**
 * Builds the value of a `Basic` Authorization header.
 *
 * `btoa` on its own is not enough: it encodes each UTF-16 code unit as one byte and throws on
 * anything above U+00FF. The server decodes the header as UTF-8 (Spring's default), so a password
 * with "€", Cyrillic or an emoji could be registered but never used to log in from the browser.
 * Encoding to UTF-8 bytes first makes both sides agree on every character.
 */
export function basicAuthHeader(email: string, password: string): string {
  return `Basic ${base64Utf8(`${email}:${password}`)}`;
}

/** Base64 of the UTF-8 bytes of `text`, for any Unicode string. */
export function base64Utf8(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
