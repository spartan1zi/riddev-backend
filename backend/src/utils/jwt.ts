import jwt from "jsonwebtoken";

const ACCESS_SECRET = () => process.env.JWT_SECRET ?? "dev-access-secret";
const REFRESH_SECRET = () => process.env.JWT_REFRESH_SECRET ?? "dev-refresh-secret";

export const ACCESS_TTL_SEC = 15 * 60;
export const REFRESH_TTL_SEC = 30 * 24 * 60 * 60;

export type JwtPayload = {
  sub: string;
  role: string;
};

export function signAccess(payload: JwtPayload): string {
  return jwt.sign(payload, ACCESS_SECRET(), { expiresIn: ACCESS_TTL_SEC });
}

export function signRefresh(payload: JwtPayload): string {
  return jwt.sign(payload, REFRESH_SECRET(), { expiresIn: REFRESH_TTL_SEC });
}

export function verifyAccess(token: string): JwtPayload {
  return jwt.verify(token, ACCESS_SECRET()) as JwtPayload;
}

export function verifyRefresh(token: string): JwtPayload {
  return jwt.verify(token, REFRESH_SECRET()) as JwtPayload;
}
