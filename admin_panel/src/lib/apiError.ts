/** Normalize Express JSON error bodies for display in the admin UI. */
export function messageFromApiBody(data: unknown, fallback: string): string {
  if (data && typeof data === "object" && "error" in data) {
    const e = (data as { error: unknown }).error;
    if (typeof e === "string") return e;
    if (e && typeof e === "object") return JSON.stringify(e);
  }
  return fallback;
}
