export function apiBaseUrl(): string {
  if (typeof window !== "undefined") {
    return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000";
  }
  return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000";
}

export const ADMIN_TOKEN_KEY = "riddev_admin_token";
/** Stored so we can renew short-lived access JWTs via POST /api/auth/refresh */
export const ADMIN_REFRESH_KEY = "riddev_admin_refresh";
