import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import { JobStatus, UserRole } from "@prisma/client";
import { param } from "../utils/params";
import { validateNoContactInfo } from "../utils/contactInfoGuard";

const router = Router();

router.post(
  "/",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        jobId: z.string().uuid(),
        revieweeId: z.string().uuid(),
        rating: z.number().int().min(1).max(5),
        comment: z.string().optional(),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const comment = parsed.data.comment?.trim();
    if (comment) {
      const check = validateNoContactInfo(comment);
      if (!check.ok) {
        res.status(400).json({ error: check.message, code: "CONTACT_INFO_NOT_ALLOWED" });
        return;
      }
    }
    const job = await prisma.job.findFirst({
      where: {
        id: parsed.data.jobId,
        customerId: req.user!.dbId,
        status: JobStatus.COMPLETED,
        workerId: parsed.data.revieweeId,
      },
    });
    if (!job) {
      res.status(400).json({ error: "Invalid job for review" });
      return;
    }
    const review = await prisma.review.create({
      data: {
        jobId: job.id,
        reviewerId: req.user!.dbId,
        revieweeId: parsed.data.revieweeId,
        rating: parsed.data.rating,
        comment: comment && comment.length > 0 ? comment : undefined,
      },
    });
    res.status(201).json(review);
  }
);

router.get("/:workerId", async (req, res) => {
  const reviews = await prisma.review.findMany({
    where: { revieweeId: param(req, "workerId") },
    orderBy: { createdAt: "desc" },
    take: 50,
  });
  res.json({ reviews });
});

export default router;
