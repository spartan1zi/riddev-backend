import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import {
  BackgroundCheckStatus,
  DisputeStatus,
  JobStatus,
  TransactionStatus,
  UserRole,
  WalletLedgerType,
} from "@prisma/client";
import { param } from "../utils/params";
import {
  notifyDisputeChatSettingsEvent,
  notifyJobChange,
  notifyUserNotificationsChanged,
} from "../lib/realtime";
import { creditWalletLedger, debitWalletLedger } from "../services/wallet";
import { sendPushToUser } from "../services/pushNotifications";

const router = Router();

router.use(authMiddleware([UserRole.ADMIN]));

router.get("/workers", async (_req, res) => {
  const workers = await prisma.user.findMany({
    where: { role: UserRole.WORKER },
    include: {
      workerProfile: true,
      wallet: { select: { balancePesewas: true, isLocked: true } },
    },
    orderBy: { createdAt: "desc" },
    take: 500,
  });
  res.json({ workers });
});

router.get("/users", async (_req: AuthedRequest, res: Response) => {
  const users = await prisma.user.findMany({
    orderBy: { createdAt: "desc" },
    take: 500,
    select: {
      id: true,
      name: true,
      email: true,
      phone: true,
      role: true,
      isActive: true,
      isSuspended: true,
      createdAt: true,
      wallet: { select: { balancePesewas: true, isLocked: true } },
    },
  });
  res.json({ users });
});

router.put(
  "/users/:id/suspend",
  async (req: AuthedRequest, res: Response) => {
    const parsed = z.object({ suspend: z.boolean() }).safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const u = await prisma.user.update({
      where: { id: param(req, "id") },
      data: { isSuspended: parsed.data.suspend },
    });
    res.json(u);
  }
);

router.get("/jobs", async (_req, res) => {
  const jobs = await prisma.job.findMany({
    orderBy: { createdAt: "desc" },
    take: 500,
    include: {
      customer: { select: { id: true, name: true, email: true } },
      worker: { select: { id: true, name: true, email: true } },
    },
  });
  res.json({ jobs });
});

/** Paystack / escrow payment rows (Transaction model) — full log for admin. */
router.get("/payments", async (_req, res) => {
  const transactions = await prisma.transaction.findMany({
    orderBy: { createdAt: "desc" },
    take: 500,
    include: {
      job: { select: { id: true, title: true, status: true } },
      customer: { select: { id: true, name: true, email: true } },
      worker: { select: { id: true, name: true, email: true } },
    },
  });
  res.json({ transactions });
});

router.get("/disputes", async (req: AuthedRequest, res: Response) => {
  const includeResolved = req.query.includeResolved === "true";
  const disputes = await prisma.dispute.findMany({
    where: includeResolved ? {} : { status: { not: DisputeStatus.RESOLVED } },
    include: {
      job: {
        include: {
          customer: { select: { id: true, name: true, email: true } },
          worker: { select: { id: true, name: true, email: true } },
        },
      },
      raisedBy: { select: { id: true, name: true, email: true, role: true } },
    },
    orderBy: { createdAt: "desc" },
    take: 200,
  });
  res.json({ disputes });
});

router.get("/disputes/:id", async (req: AuthedRequest, res: Response) => {
  const dispute = await prisma.dispute.findUnique({
    where: { id: param(req, "id") },
    include: {
      job: {
        include: {
          customer: { select: { id: true, name: true, email: true } },
          worker: { select: { id: true, name: true, email: true } },
        },
      },
      raisedBy: { select: { id: true, name: true, email: true, role: true } },
    },
  });
  if (!dispute) {
    res.status(404).json({ error: "Dispute not found" });
    return;
  }
  res.json({ dispute });
});

/**
 * Toggle Everyone channel for customer/worker + full dispute chat lock.
 * Notifies customer + worker in-app; emits realtime for open apps.
 */
router.patch("/disputes/:id/chat-settings", async (req: AuthedRequest, res: Response) => {
  const parsed = z
    .object({
      everyoneChannelEnabled: z.boolean().optional(),
      disputeChatLocked: z.boolean().optional(),
    })
    .refine((d) => d.everyoneChannelEnabled !== undefined || d.disputeChatLocked !== undefined, {
      message: "Provide everyoneChannelEnabled and/or disputeChatLocked",
    })
    .safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const disputeId = param(req, "id");
  const before = await prisma.dispute.findUnique({
    where: { id: disputeId },
    include: { job: true },
  });
  if (!before) {
    res.status(404).json({ error: "Dispute not found" });
    return;
  }

  const data: { everyoneChannelEnabled?: boolean; disputeChatLocked?: boolean } = {};
  if (parsed.data.everyoneChannelEnabled !== undefined) {
    data.everyoneChannelEnabled = parsed.data.everyoneChannelEnabled;
  }
  if (parsed.data.disputeChatLocked !== undefined) {
    data.disputeChatLocked = parsed.data.disputeChatLocked;
  }

  const updated = await prisma.dispute.update({
    where: { id: disputeId },
    data,
  });

  const partyIds = [before.job.customerId, before.job.workerId].filter(
    (x): x is string => typeof x === "string" && x.length > 0
  );

  type Notif = { title: string; body: string };
  const toSend: Notif[] = [];
  if (
    parsed.data.everyoneChannelEnabled === true &&
    !before.everyoneChannelEnabled
  ) {
    toSend.push({
      title: "Group discussion opened",
      body: "Admin has opened the group discussion for your dispute.",
    });
  }
  if (
    parsed.data.everyoneChannelEnabled === false &&
    before.everyoneChannelEnabled
  ) {
    toSend.push({
      title: "Group discussion paused",
      body: "Admin has paused the group discussion.",
    });
  }
  if (parsed.data.disputeChatLocked === true && !before.disputeChatLocked) {
    toSend.push({
      title: "Dispute chat locked",
      body: "This dispute chat has been locked by admin. Please wait for further instructions.",
    });
  }
  if (parsed.data.disputeChatLocked === false && before.disputeChatLocked) {
    toSend.push({
      title: "Dispute chat unlocked",
      body: "Admin has unlocked the dispute chat.",
    });
  }

  if (toSend.length > 0 && partyIds.length > 0) {
    const creates = toSend.flatMap((n) =>
      partyIds.map((userId) =>
        prisma.notification.create({
          data: {
            userId,
            title: n.title,
            body: n.body,
            type: "dispute_chat_control",
            data: { disputeId },
          },
        })
      )
    );
    await prisma.$transaction(creates);
    for (const uid of new Set(partyIds)) {
      notifyUserNotificationsChanged(uid, { reason: "dispute_chat_control" });
    }
    for (const n of toSend) {
      for (const userId of partyIds) {
        void sendPushToUser(userId, n.title, n.body, {
          disputeId,
          type: "dispute_chat_control",
        });
      }
    }
  }

  void notifyDisputeChatSettingsEvent(disputeId, {
    everyoneChannelEnabled: updated.everyoneChannelEnabled,
    disputeChatLocked: updated.disputeChatLocked,
  });

  res.json({ dispute: updated });
});

/** All funds currently held in escrow (pending release or dispute resolution). */
router.get("/escrow/holdings", async (_req: AuthedRequest, res: Response) => {
  const held = await prisma.transaction.findMany({
    where: { status: TransactionStatus.HELD },
    include: {
      job: {
        select: {
          id: true,
          title: true,
          status: true,
          customerId: true,
          workerId: true,
        },
      },
      customer: { select: { id: true, name: true, email: true } },
      worker: { select: { id: true, name: true, email: true } },
    },
    orderBy: { createdAt: "desc" },
    take: 500,
  });
  res.json({ holdings: held });
});

/**
 * Resolve a dispute by moving HELD escrow either back to the customer (wallet credit)
 * or to the worker (same path as normal payment release). Prevents double-spend: one HELD txn per job.
 */
router.post(
  "/disputes/:id/settle",
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        outcome: z.enum(["REFUND_CUSTOMER", "PAY_WORKER"]),
        resolution: z.string().min(10).max(4000),
        adminNotes: z.string().max(4000).optional(),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const disputeId = param(req, "id");
    const { outcome, resolution, adminNotes } = parsed.data;

    try {
      const result = await prisma.$transaction(async (tx) => {
        const dispute = await tx.dispute.findUnique({
          where: { id: disputeId },
          include: { job: true },
        });
        if (!dispute) {
          throw new Error("DISPUTE_NOT_FOUND");
        }
        if (dispute.status === DisputeStatus.RESOLVED) {
          throw new Error("ALREADY_RESOLVED");
        }
        const job = dispute.job;
        const held = await tx.transaction.findFirst({
          where: { jobId: job.id, status: TransactionStatus.HELD },
        });
        if (!held) {
          throw new Error("NO_HELD_ESCROW");
        }

        if (outcome === "REFUND_CUSTOMER") {
          await creditWalletLedger(
            tx,
            job.customerId,
            held.amountPesewas,
            WalletLedgerType.REFUND,
            `Escrow refunded after dispute resolution. Job: ${job.title}`,
            {
              jobId: job.id,
              reference: `dispute_refund_${held.id}`,
              bypassWalletLock: true,
            }
          );
          await tx.transaction.update({
            where: { id: held.id },
            data: { status: TransactionStatus.REFUNDED },
          });
          await tx.job.update({
            where: { id: job.id },
            data: { status: JobStatus.CANCELLED },
          });
        } else {
          if (!job.workerId) {
            throw new Error("NO_WORKER_ON_JOB");
          }
          await tx.transaction.update({
            where: { id: held.id },
            data: { status: TransactionStatus.RELEASED, releasedAt: new Date() },
          });
          await tx.job.update({
            where: { id: job.id },
            data: { status: JobStatus.COMPLETED, completedAt: new Date() },
          });
          await tx.workerProfile.update({
            where: { userId: job.workerId },
            data: { totalJobsCompleted: { increment: 1 } },
          });
          await creditWalletLedger(
            tx,
            job.workerId!,
            held.workerAmountPesewas,
            WalletLedgerType.JOB_PAYMENT,
            `Earnings after dispute resolution (admin: pay worker). Job: ${job.title}`,
            { jobId: job.id, reference: held.id, bypassWalletLock: true }
          );
        }

        const updated = await tx.dispute.update({
          where: { id: disputeId },
          data: {
            status: DisputeStatus.RESOLVED,
            resolution,
            adminNotes: adminNotes ?? null,
            resolvedAt: new Date(),
          },
        });
        return { jobId: job.id, dispute: updated };
      });

      void notifyJobChange(result.jobId, "dispute_settled");
      res.json({ ok: true, dispute: result.dispute });
    } catch (e) {
      const code = e instanceof Error ? e.message : "UNKNOWN";
      const map: Record<string, number> = {
        DISPUTE_NOT_FOUND: 404,
        ALREADY_RESOLVED: 400,
        NO_HELD_ESCROW: 400,
        NO_WORKER_ON_JOB: 400,
      };
      const status = map[code] ?? 500;
      const msg =
        code === "NO_HELD_ESCROW"
          ? "No HELD escrow for this job — it may already be released or refunded."
          : code === "ALREADY_RESOLVED"
            ? "Dispute is already resolved."
            : code === "NO_WORKER_ON_JOB"
              ? "Cannot pay worker: job has no worker assigned."
              : code === "DISPUTE_NOT_FOUND"
                ? "Dispute not found."
                : e instanceof Error
                  ? e.message
                  : "Settlement failed";
      res.status(status).json({ error: msg });
    }
  }
);

router.put(
  "/workers/:id/verify",
  async (req: AuthedRequest, res: Response) => {
    const wp = await prisma.workerProfile.update({
      where: { userId: param(req, "id") },
      data: { backgroundCheckStatus: BackgroundCheckStatus.APPROVED },
    });
    res.json(wp);
  }
);

router.post(
  "/wallet/credit",
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        userId: z.string().uuid(),
        amountPesewas: z.number().int().positive(),
        reason: z.string().min(3).max(500),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const { userId, amountPesewas, reason } = parsed.data;
    await prisma.$transaction(async (tx) => {
      await creditWalletLedger(
        tx,
        userId,
        amountPesewas,
        WalletLedgerType.ADMIN_CREDIT,
        `Admin credit: ${reason}`,
        { reference: `admin_credit_${req.user!.dbId}_${Date.now()}` }
      );
    });
    const w = await prisma.wallet.findUnique({ where: { userId } });
    res.json({ ok: true, balancePesewas: w?.balancePesewas ?? amountPesewas });
  }
);

router.post(
  "/wallet/debit",
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        userId: z.string().uuid(),
        amountPesewas: z.number().int().positive(),
        reason: z.string().min(3).max(500),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const { userId, amountPesewas, reason } = parsed.data;
    try {
      await prisma.$transaction(async (tx) => {
        await debitWalletLedger(
          tx,
          userId,
          amountPesewas,
          WalletLedgerType.ADMIN_DEBIT,
          `Admin debit: ${reason}`,
          { reference: `admin_debit_${req.user!.dbId}_${Date.now()}` }
        );
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Debit failed";
      res.status(400).json({ error: msg });
      return;
    }
    const w = await prisma.wallet.findUnique({ where: { userId } });
    res.json({ ok: true, balancePesewas: w?.balancePesewas ?? 0 });
  }
);

router.put(
  "/wallet/lock/:userId",
  async (req: AuthedRequest, res: Response) => {
    const parsed = z.object({ locked: z.boolean() }).safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const wallet = await prisma.wallet.upsert({
      where: { userId: param(req, "userId") },
      create: { userId: param(req, "userId"), balancePesewas: 0, isLocked: parsed.data.locked },
      update: { isLocked: parsed.data.locked },
    });
    res.json(wallet);
  }
);

router.get("/analytics", async (_req, res) => {
  const [userCount, jobCount, revenue] = await Promise.all([
    prisma.user.count(),
    prisma.job.count(),
    prisma.transaction.aggregate({
      where: { status: "RELEASED" },
      _sum: { amountPesewas: true },
    }),
  ]);
  res.json({
    totalUsers: userCount,
    totalJobs: jobCount,
    revenuePesewas: revenue._sum.amountPesewas ?? 0,
  });
});

export default router;
