import type { Request } from "express";

export function param(req: Request, key: string): string {
  const v = req.params[key];
  if (Array.isArray(v)) return v[0] ?? "";
  return typeof v === "string" ? v : "";
}
