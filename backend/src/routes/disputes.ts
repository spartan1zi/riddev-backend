import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import {
  DisputeMessageChannel,
  DisputeStatus,
  JobStatus,
  TransactionStatus,
  UserRole,
} from "@prisma/client";
import { param } from "../utils/params";
import { validateNoContactInfo } from "../utils/contactInfoGuard";
import { notifyDisputeMessageEvent, notifyUserNotificationsChanged } from "../lib/realtime";
import { sendPushToUser } from "../services/pushNotifications";

const router = Router();

async function loadDisputeWithJob(disputeId: string) {
  return prisma.dispute.findUnique({
    where: { id: disputeId },
    include: { job: true },
  });
}

function canAccessDispute(
  d: { job: { customerId: string; workerId: string | null } },
  userId: string,
  role: string
): boolean {
  if (role === UserRole.ADMIN) return true;
  if (d.job.customerId === userId) return true;
  if (d.job.workerId === userId) return true;
  return false;
}

function sortByCreatedAt<T extends { createdAt: Date }>(a: T, b: T): number {
  return a.createdAt.getTime() - b.createdAt.getTime();
}

function chatSettingsPayload(d: { everyoneChannelEnabled: boolean; disputeChatLocked: boolean }) {
  return {
    everyoneChannelEnabled: d.everyoneChannelEnabled,
    disputeChatLocked: d.disputeChatLocked,
  };
}

/** In-app (+ optional FCM later) notifications for dispute messages — never notifies the sender. */
async function notifyDisputeMessageRecipients(params: {
  disputeId: string;
  messageId: string;
  channel: DisputeMessageChannel;
  senderId: string;
  senderRole: UserRole;
  jobCustomerId: string;
  jobWorkerId: string | null;
  /** When false and sender is admin on ALL, use broadcast notification copy for customer/worker. */
  everyoneChannelEnabled: boolean;
}): Promise<void> {
  const {
    disputeId,
    messageId,
    channel,
    senderId,
    senderRole,
    jobCustomerId,
    jobWorkerId,
    everyoneChannelEnabled,
  } = params;
  const shortId = disputeId.replace(/-/g, "").slice(0, 8);

  const baseData = {
    disputeId,
    messageId,
    channel,
    senderId,
  };

  type Row = { userId: string; title: string; body: string };
  const rows: Row[] = [];

  function add(userId: string, title: string, body: string) {
    if (userId === senderId) return;
    rows.push({ userId, title, body });
  }

  const adminUsers = await prisma.user.findMany({
    where: { role: UserRole.ADMIN },
    select: { id: true },
  });

  if (channel === DisputeMessageChannel.ADMIN_CUSTOMER) {
    if (senderRole === UserRole.ADMIN) {
      add(jobCustomerId, "Support message in your dispute", "You have a new message in You & Support Only");
    } else {
      for (const a of adminUsers) {
        add(
          a.id,
          `Customer replied in dispute #${shortId}`,
          "New message in You & Support Only from customer"
        );
      }
    }
  } else if (channel === DisputeMessageChannel.ADMIN_WORKER) {
    if (senderRole === UserRole.ADMIN) {
      if (jobWorkerId) {
        add(jobWorkerId, "Support message in your dispute", "You have a new message in You & Support Only");
      }
    } else {
      for (const a of adminUsers) {
        add(
          a.id,
          `Worker replied in dispute #${shortId}`,
          "New message in You & Support Only from worker"
        );
      }
    }
  } else {
    // ALL
    if (senderRole === UserRole.ADMIN) {
      const title = !everyoneChannelEnabled ? "Message from support" : "New message in dispute";
      const body = !everyoneChannelEnabled
        ? "Admin posted in Everyone — tap to read"
        : "Admin sent a message in Everyone";
      add(jobCustomerId, title, body);
      if (jobWorkerId) {
        add(jobWorkerId, title, body);
      }
    } else if (senderRole === UserRole.CUSTOMER) {
      if (jobWorkerId) {
        add(jobWorkerId, "New message in dispute", "Customer sent a message in Everyone");
      }
      for (const a of adminUsers) {
        add(
          a.id,
          `Customer sent in Everyone — dispute #${shortId}`,
          "New message in Everyone channel"
        );
      }
    } else if (senderRole === UserRole.WORKER) {
      add(jobCustomerId, "New message in dispute", "Worker sent a message in Everyone");
      for (const a of adminUsers) {
        add(
          a.id,
          `Worker sent in Everyone — dispute #${shortId}`,
          "New message in Everyone channel"
        );
      }
    }
  }

  if (rows.length === 0) return;

  await prisma.$transaction(
    rows.map((r) =>
      prisma.notification.create({
        data: {
          userId: r.userId,
          title: r.title,
          body: r.body,
          type: "dispute_message",
          data: baseData,
        },
      })
    )
  );

  const recipientIds = new Set(rows.map((r) => r.userId));
  for (const uid of recipientIds) {
    notifyUserNotificationsChanged(uid, { reason: "dispute_message" });
  }

  const pushData: Record<string, string> = {
    disputeId,
    messageId,
    channel: String(channel),
    senderId,
    type: "dispute_message",
  };
  for (const r of rows) {
    void sendPushToUser(r.userId, r.title, r.body, pushData);
  }
}

/** Disputes involving this user (raised the dispute, or customer/worker on the job). */
router.get("/mine", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.dbId;
  const disputes = await prisma.dispute.findMany({
    where: {
      OR: [{ raisedById: uid }, { job: { customerId: uid } }, { job: { workerId: uid } }],
    },
    include: {
      job: { select: { id: true, title: true, status: true } },
      raisedBy: { select: { id: true, name: true, role: true } },
    },
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  res.json({ disputes });
});

router.post(
  "/",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        jobId: z.string().uuid(),
        reason: z.string().min(10),
        evidencePhotos: z.array(z.string().url()).max(12).default([]),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const job = await prisma.job.findUnique({ where: { id: parsed.data.jobId } });
    if (!job) {
      res.status(404).json({ error: "Job not found" });
      return;
    }
    const uid = req.user!.dbId;
    if (job.customerId !== uid && job.workerId !== uid) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
    const held = await prisma.transaction.findFirst({
      where: { jobId: job.id, status: TransactionStatus.HELD },
    });
    if (!held) {
      res.status(400).json({
        error:
          "No funds in escrow for this job yet. Disputes about payment can be opened after the customer has paid and funds are held.",
      });
      return;
    }
    const existingOpen = await prisma.dispute.findFirst({
      where: {
        jobId: job.id,
        status: { in: [DisputeStatus.OPEN, DisputeStatus.UNDER_REVIEW] },
      },
    });
    if (existingOpen) {
      res.status(400).json({ error: "A dispute is already open for this job." });
      return;
    }
    if (job.status === JobStatus.COMPLETED || job.status === JobStatus.CANCELLED) {
      res.status(400).json({ error: "Cannot open a dispute on a completed or cancelled job." });
      return;
    }
    const d = await prisma.dispute.create({
      data: {
        jobId: job.id,
        raisedById: uid,
        reason: parsed.data.reason,
        evidencePhotos: parsed.data.evidencePhotos,
        status: DisputeStatus.OPEN,
      },
    });
    await prisma.job.update({
      where: { id: job.id },
      data: { status: "DISPUTED" },
    });
    res.status(201).json(d);
  }
);

router.get(
  "/:id/messages",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const disputeId = param(req, "id");
    const d = await loadDisputeWithJob(disputeId);
    if (!d) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    if (!canAccessDispute(d, req.user!.dbId, req.user!.role)) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
    const rows = await prisma.disputeMessage.findMany({
      where: { disputeId },
      include: {
        sender: { select: { id: true, name: true, email: true, role: true } },
      },
      orderBy: { createdAt: "asc" },
      take: 500,
    });

    const role = req.user!.role;
    const uid = req.user!.dbId;

    if (role === UserRole.ADMIN) {
      const channels = {
        ALL: rows.filter((m) => m.channel === DisputeMessageChannel.ALL),
        ADMIN_CUSTOMER: rows.filter((m) => m.channel === DisputeMessageChannel.ADMIN_CUSTOMER),
        ADMIN_WORKER: rows.filter((m) => m.channel === DisputeMessageChannel.ADMIN_WORKER),
      };
      res.json({ channels, chatSettings: chatSettingsPayload(d) });
      return;
    }

    if (d.job.customerId === uid) {
      const allOnly = rows
        .filter((m) => m.channel === DisputeMessageChannel.ALL)
        .sort(sortByCreatedAt);
      const adminCustomer = rows
        .filter((m) => m.channel === DisputeMessageChannel.ADMIN_CUSTOMER)
        .sort(sortByCreatedAt);
      res.json({
        channels: { ALL: allOnly, ADMIN_CUSTOMER: adminCustomer },
        chatSettings: chatSettingsPayload(d),
      });
      return;
    }

    if (d.job.workerId === uid) {
      const allOnly = rows
        .filter((m) => m.channel === DisputeMessageChannel.ALL)
        .sort(sortByCreatedAt);
      const adminWorker = rows
        .filter((m) => m.channel === DisputeMessageChannel.ADMIN_WORKER)
        .sort(sortByCreatedAt);
      res.json({
        channels: { ALL: allOnly, ADMIN_WORKER: adminWorker },
        chatSettings: chatSettingsPayload(d),
      });
      return;
    }

    res.status(403).json({ error: "Forbidden" });
  }
);

const postMessageSchema = z
  .object({
    body: z.string().max(8000).optional(),
    imageUrls: z.array(z.string().url()).max(8).optional(),
    channel: z.nativeEnum(DisputeMessageChannel).optional(),
  })
  .refine(
    (d) => {
      const t = (d.body ?? "").trim();
      const imgs = d.imageUrls ?? [];
      return t.length > 0 || imgs.length > 0;
    },
    { message: "Message must include text and/or image URLs" }
  );

router.post(
  "/:id/messages",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = postMessageSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const trimmed = (parsed.data.body ?? "").trim();
    const imageUrls = parsed.data.imageUrls ?? [];
    const channel = parsed.data.channel ?? DisputeMessageChannel.ALL;

    const disputeId = param(req, "id");
    const d = await loadDisputeWithJob(disputeId);
    if (!d) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    if (!canAccessDispute(d, req.user!.dbId, req.user!.role)) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }

    const uid = req.user!.dbId;
    const userRole = req.user!.role;

    if (userRole !== UserRole.ADMIN && d.disputeChatLocked) {
      res.status(403).json({
        error:
          "This dispute chat has been locked by admin. Please wait for further instructions.",
      });
      return;
    }

    if (userRole === UserRole.CUSTOMER) {
      if (d.job.customerId !== uid) {
        res.status(403).json({ error: "Forbidden" });
        return;
      }
      if (channel !== DisputeMessageChannel.ALL && channel !== DisputeMessageChannel.ADMIN_CUSTOMER) {
        res.status(400).json({
          error: "Customers can only post to Everyone or Admin + you.",
        });
        return;
      }
    } else if (userRole === UserRole.WORKER) {
      if (d.job.workerId !== uid) {
        res.status(403).json({ error: "Forbidden" });
        return;
      }
      if (channel !== DisputeMessageChannel.ALL && channel !== DisputeMessageChannel.ADMIN_WORKER) {
        res.status(400).json({
          error: "Workers can only post to Everyone or Admin + you.",
        });
        return;
      }
    } else if (userRole !== UserRole.ADMIN) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }

    if (
      userRole !== UserRole.ADMIN &&
      channel === DisputeMessageChannel.ALL &&
      !d.everyoneChannelEnabled
    ) {
      res.status(403).json({
        error:
          "This channel is not open yet. An admin must enable group discussion before you can post here.",
      });
      return;
    }

    if (trimmed.length > 0 && userRole !== UserRole.ADMIN) {
      const contactCheck = validateNoContactInfo(trimmed);
      if (!contactCheck.ok) {
        res.status(400).json({
          error: contactCheck.message,
          code: "CONTACT_INFO_NOT_ALLOWED",
        });
        return;
      }
    }

    const msg = await prisma.disputeMessage.create({
      data: {
        disputeId,
        senderId: req.user!.dbId,
        body: trimmed.length > 0 ? trimmed : "(Images attached)",
        imageUrls,
        channel,
      },
      include: {
        sender: { select: { id: true, name: true, email: true, role: true } },
      },
    });

    if (d.status === DisputeStatus.OPEN) {
      await prisma.dispute.update({
        where: { id: disputeId },
        data: { status: DisputeStatus.UNDER_REVIEW },
      });
    }

    try {
      await notifyDisputeMessageRecipients({
        disputeId,
        messageId: msg.id,
        channel,
        senderId: uid,
        senderRole: msg.sender.role,
        jobCustomerId: d.job.customerId,
        jobWorkerId: d.job.workerId,
        everyoneChannelEnabled: d.everyoneChannelEnabled,
      });
    } catch (notifErr) {
      console.error("[disputes] notifyDisputeMessageRecipients", notifErr);
    }

    void notifyDisputeMessageEvent(disputeId, {
      disputeId,
      message: msg,
    });

    res.status(201).json({ message: msg });
  }
);

router.get("/:id", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const d = await prisma.dispute.findUnique({
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
  if (!d) {
    res.status(404).json({ error: "Not found" });
    return;
  }
  const uid = req.user!.dbId;
  if (
    d.job.customerId !== uid &&
    d.job.workerId !== uid &&
    req.user!.role !== UserRole.ADMIN
  ) {
    res.status(403).json({ error: "Forbidden" });
    return;
  }
  res.json(d);
});

router.put(
  "/:id/resolve",
  authMiddleware([UserRole.ADMIN]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        resolution: z.string(),
        adminNotes: z.string().optional(),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const d = await prisma.dispute.update({
      where: { id: param(req, "id") },
      data: {
        status: DisputeStatus.RESOLVED,
        resolution: parsed.data.resolution,
        adminNotes: parsed.data.adminNotes,
        resolvedAt: new Date(),
      },
    });
    res.json(d);
  }
);

export default router;
