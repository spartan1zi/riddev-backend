import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import { JobStatus, QuoteStatus, UserRole } from "@prisma/client";
import { computeFees } from "../utils/pricing";
import { param } from "../utils/params";
import { notifyJobChange, notifyUserNotificationsChanged } from "../lib/realtime";
import { sendPushToUser } from "../services/pushNotifications";

const router = Router();

router.put(
  "/:id/accept",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const quoteId = param(req, "id");
    const quote = await prisma.quote.findUnique({
      where: { id: quoteId },
      include: { job: true, worker: { include: { workerProfile: true } } },
    });
    if (!quote || quote.job.customerId !== req.user!.dbId) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    if (quote.status !== QuoteStatus.PENDING && quote.status !== QuoteStatus.COUNTERED) {
      res.status(400).json({ error: "Quote not actionable" });
      return;
    }
    const bps = quote.worker.workerProfile?.commissionRateBps ?? 1500;
    const agreed = quote.counterAmountPesewas ?? quote.amountPesewas;
    const fees = computeFees(agreed, bps);
    await prisma.$transaction([
      prisma.quote.updateMany({
        where: { jobId: quote.jobId, id: { not: quote.id } },
        data: { status: QuoteStatus.REJECTED },
      }),
      prisma.quote.update({
        where: { id: quote.id },
        data: { status: QuoteStatus.ACCEPTED },
      }),
      prisma.job.update({
        where: { id: quote.jobId },
        data: {
          status: JobStatus.ACCEPTED,
          workerId: quote.workerId,
          agreedPricePesewas: agreed,
          platformFeePesewas: fees.platformFeePesewas,
          workerPayoutPesewas: fees.workerPayoutPesewas,
          trustFeePesewas: fees.trustFeePesewas,
          quoteAcceptedAt: new Date(),
        },
      }),
      prisma.notification.create({
        data: {
          userId: quote.job.customerId,
          title: "Complete payment",
          body: `Pay to hold funds in escrow for "${quote.job.title}". Messaging your worker unlocks after payment.`,
          type: "payment_pending",
          data: { jobId: quote.jobId },
        },
      }),
    ]);
    notifyUserNotificationsChanged(quote.job.customerId, { reason: "payment_pending" });
    void sendPushToUser(
      quote.job.customerId,
      "Complete payment",
      `Pay to hold funds in escrow for "${quote.job.title}". Messaging your worker unlocks after payment.`,
      { jobId: quote.jobId, type: "payment_pending" }
    );
    void notifyJobChange(quote.jobId, "quote_accepted");
    res.json({ ok: true, customerTotalPesewas: fees.customerTotalPesewas });
  }
);

router.put(
  "/:id/reject",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const quote = await prisma.quote.findUnique({
      where: { id: param(req, "id") },
      include: { job: true },
    });
    if (!quote || quote.job.customerId !== req.user!.dbId) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    await prisma.quote.update({
      where: { id: quote.id },
      data: { status: QuoteStatus.REJECTED },
    });
    void notifyJobChange(quote.jobId, "quote_rejected");
    res.json({ ok: true });
  }
);

router.put(
  "/:id/counter",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({ counterAmountPesewas: z.number().int().positive() })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const quote = await prisma.quote.findUnique({
      where: { id: param(req, "id") },
      include: { job: true },
    });
    if (!quote || quote.job.customerId !== req.user!.dbId) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const updated = await prisma.quote.update({
      where: { id: quote.id },
      data: {
        status: QuoteStatus.COUNTERED,
        counterAmountPesewas: parsed.data.counterAmountPesewas,
      },
    });
    void notifyJobChange(quote.jobId, "quote_countered");
    res.json(updated);
  }
);

router.put(
  "/:id/withdraw",
  authMiddleware([UserRole.WORKER]),
  async (req: AuthedRequest, res: Response) => {
    const quote = await prisma.quote.findUnique({ where: { id: param(req, "id") } });
    if (!quote || quote.workerId !== req.user!.dbId) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    await prisma.quote.update({
      where: { id: quote.id },
      data: { status: QuoteStatus.REJECTED },
    });
    void notifyJobChange(quote.jobId, "quote_withdrawn");
    res.json({ ok: true });
  }
);

export default router;
