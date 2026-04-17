import { ADMIN_REFRESH_KEY, ADMIN_TOKEN_KEY } from "./config";

export function getAdminToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(ADMIN_TOKEN_KEY);
}

export function setAdminToken(token: string): void {
  localStorage.setItem(ADMIN_TOKEN_KEY, token);
}

export function clearAdminToken(): void {
  localStorage.removeItem(ADMIN_TOKEN_KEY);
}

export function getAdminRefreshToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(ADMIN_REFRESH_KEY);
}

export function setAdminRefreshToken(token: string): void {
  localStorage.setItem(ADMIN_REFRESH_KEY, token);
}

export function clearAdminRefreshToken(): void {
  localStorage.removeItem(ADMIN_REFRESH_KEY);
}

/** Clear access + refresh (call on logout) */
export function clearAdminSession(): void {
  clearAdminToken();
  clearAdminRefreshToken();
}
