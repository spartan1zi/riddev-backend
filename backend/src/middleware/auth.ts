import type { Request, Response, NextFunction } from "express";
import { verifyAccess, type JwtPayload } from "../utils/jwt";
import { prisma } from "../lib/prisma";
import type { UserRole } from "@prisma/client";

export type AuthedRequest = Request & {
  user?: JwtPayload & { dbId: string };
};

export function authMiddleware(requiredRoles?: UserRole[]) {
  return async (req: AuthedRequest, res: Response, next: NextFunction) => {
    const header = req.headers.authorization;
    if (!header?.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing bearer token" });
      return;
    }
    const token = header.slice(7);
    try {
      const payload = verifyAccess(token);
      const user = await prisma.user.findUnique({ where: { id: payload.sub } });
      if (!user || user.isSuspended || !user.isActive) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }
      if (requiredRoles?.length && !requiredRoles.includes(user.role)) {
        res.status(403).json({ error: "Forbidden" });
        return;
      }
      req.user = { ...payload, dbId: user.id };
      next();
    } catch {
      res.status(401).json({ error: "Invalid token" });
    }
  };
}
