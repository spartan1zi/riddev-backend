import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { JobStatus, TransactionStatus, UserRole } from "@prisma/client";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import { validateNoContactInfo } from "../utils/contactInfoGuard";
import { param } from "../utils/params";
import { emitToJobRoom, notifyJobChange } from "../lib/realtime";

const router = Router();

/** Same idea as `GET /jobs/:id/quotes`: customer, assigned worker, quoting workers, admin. */
async function canAccessJobChat(
  job: { id: string; customerId: string; workerId: string | null },
  uid: string,
  role: UserRole
): Promise<boolean> {
  if (job.customerId === uid) return true;
  if (job.workerId === uid) return true;
  if (role === UserRole.ADMIN) return true;
  const quoted = await prisma.quote.findFirst({
    where: { jobId: job.id, workerId: uid },
    select: { id: true },
  });
  return quoted !== null;
}

/** Customer may open chat only after escrow is held for accepted / in-progress jobs. */
async function customerAllowedToChat(
  job: { id: string; customerId: string; status: JobStatus },
  uid: string,
  role: UserRole
): Promise<boolean> {
  if (role !== UserRole.CUSTOMER || job.customerId !== uid) return true;
  if (job.status !== JobStatus.ACCEPTED && job.status !== JobStatus.IN_PROGRESS) {
    return true;
  }
  const held = await prisma.transaction.findFirst({
    where: { jobId: job.id, status: TransactionStatus.HELD },
    select: { id: true },
  });
  return held != null;
}

router.get(
  "/:jobId",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const job = await prisma.job.findUnique({ where: { id: param(req, "jobId") } });
    if (!job) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const uid = req.user!.dbId;
    if (!(await canAccessJobChat(job, uid, req.user!.role as UserRole))) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
    if (!(await customerAllowedToChat(job, uid, req.user!.role as UserRole))) {
      res.status(403).json({
        error:
          "Complete payment first. Messaging unlocks after funds are held in escrow.",
        code: "PAYMENT_REQUIRED",
      });
      return;
    }
    const messages = await prisma.chatMessage.findMany({
      where: { jobId: job.id },
      orderBy: { timestamp: "asc" },
      take: 500,
    });
    res.json({ messages });
  }
);

router.post(
  "/:jobId",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z.object({ content: z.string().min(1).max(4000) }).safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    if (req.user!.role !== UserRole.ADMIN) {
      const check = validateNoContactInfo(parsed.data.content);
      if (!check.ok) {
        res.status(400).json({ error: check.message, code: "CONTACT_INFO_NOT_ALLOWED" });
        return;
      }
    }
    const job = await prisma.job.findUnique({ where: { id: param(req, "jobId") } });
    if (!job) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const uid = req.user!.dbId;
    if (!(await canAccessJobChat(job, uid, req.user!.role as UserRole))) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
    if (!(await customerAllowedToChat(job, uid, req.user!.role as UserRole))) {
      res.status(403).json({
        error:
          "Complete payment first. Messaging unlocks after funds are held in escrow.",
        code: "PAYMENT_REQUIRED",
      });
      return;
    }
    const msg = await prisma.chatMessage.create({
      data: {
        jobId: job.id,
        senderId: uid,
        content: parsed.data.content,
        isBlocked: false,
      },
    });
    emitToJobRoom(job.id, "chat:message", msg);
    void notifyJobChange(job.id, "chat", { skipWorkersFeed: true });
    res.status(201).json(msg);
  }
);

export default router;
