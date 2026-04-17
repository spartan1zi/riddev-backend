import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";

const router = Router();

router.post(
  "/off-platform",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        reportedId: z.string().uuid(),
        jobId: z.string().uuid().optional(),
        notes: z.string().optional(),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    await prisma.offPlatformReport.create({
      data: {
        reporterId: req.user!.dbId,
        reportedId: parsed.data.reportedId,
        jobId: parsed.data.jobId,
        notes: parsed.data.notes,
      },
    });
    res.status(201).json({ ok: true });
  }
);

export default router;
