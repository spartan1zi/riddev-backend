import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";

const router = Router();

router.get("/", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const items = await prisma.notification.findMany({
    where: { userId: req.user!.dbId },
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  res.json({ notifications: items });
});

router.put(
  "/read",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z.object({ ids: z.array(z.string().uuid()) }).optional().safeParse(req.body);
    if (parsed.success && parsed.data?.ids?.length) {
      await prisma.notification.updateMany({
        where: { userId: req.user!.dbId, id: { in: parsed.data.ids } },
        data: { isRead: true },
      });
    } else {
      await prisma.notification.updateMany({
        where: { userId: req.user!.dbId },
        data: { isRead: true },
      });
    }
    res.json({ ok: true });
  }
);

export default router;
