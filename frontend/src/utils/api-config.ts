/**
 * Get API URL based on current environment
 */
export function getApiUrl(): string {
  const hostname = window.location.hostname;
  const protocol = window.location.protocol;

  // If UI runs on localhost, use localhost:8080
  if (hostname === "localhost" || hostname === "127.0.0.1") {
    return "http://localhost:8080";
  }

  // If UI runs on an IP address, use same IP with port 8080
  const ipPattern = /^(\d{1,3}\.){3}\d{1,3}$/;
  if (ipPattern.test(hostname)) {
    return `${protocol}//${hostname}:8080`;
  }

  // If UI runs on a domain (not localhost or IP), use same domain without port change
  return `${protocol}//${hostname}`;
}
