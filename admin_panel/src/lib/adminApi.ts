import { apiBaseUrl } from "./config";
import {
  clearAdminSession,
  getAdminRefreshToken,
  getAdminToken,
  setAdminToken,
} from "./auth";

/**
 * Authenticated fetch for admin API routes. Retries once after POST /api/auth/refresh
 * when the access JWT expires (~15 min); login must have stored a refresh token.
 */
export async function adminApiFetch(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  const base = apiBaseUrl();
  const url = path.startsWith("http") ? path : `${base}${path.startsWith("/") ? "" : "/"}${path}`;

  const withAuth = (accessToken: string) => {
    const headers = new Headers(init.headers);
    headers.set("Authorization", `Bearer ${accessToken}`);
    return fetch(url, { ...init, headers });
  };

  const access = getAdminToken();
  if (!access) {
    return new Response(JSON.stringify({ error: "Not logged in" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const res = await withAuth(access);
  if (res.status !== 401) {
    return res;
  }

  const refresh = getAdminRefreshToken();
  if (!refresh) {
    clearAdminSession();
    if (typeof window !== "undefined") {
      window.location.assign("/login");
    }
    return res;
  }

  const refreshed = await fetch(`${base}/api/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken: refresh }),
  });
  const data: unknown = await refreshed.json().catch(() => ({}));

  if (
    !refreshed.ok ||
    !data ||
    typeof data !== "object" ||
    typeof (data as { accessToken?: unknown }).accessToken !== "string"
  ) {
    clearAdminSession();
    if (typeof window !== "undefined") {
      window.location.assign("/login");
    }
    return res;
  }

  const nextAccess = (data as { accessToken: string }).accessToken;
  setAdminToken(nextAccess);
  return withAuth(nextAccess);
}
