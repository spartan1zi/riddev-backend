import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import { notifyJobChange, notifyNewJob } from "../lib/realtime";
import {
  JobCategory,
  JobStatus,
  QuoteStatus,
  TransactionStatus,
  UserRole,
} from "@prisma/client";
import { ALL_JOB_CATEGORIES } from "../constants/jobCategories";
import { distanceKm } from "../utils/geo";
import { serializeWorkerPublic } from "../services/workerSerialize";
import { param } from "../utils/params";
import { validateNoContactInfo } from "../utils/contactInfoGuard";
import { v4 as uuidv4 } from "uuid";

const QUOTE_EXPIRY_MS = 2 * 60 * 60 * 1000;
const MAX_QUOTES = 5;
const MAX_QUOTE_KM = 20;

/** Default map centre (Accra) when worker has not set base location yet. */
const DEFAULT_BASE_LAT = 5.6037;
const DEFAULT_BASE_LNG = -0.187;

function categoriesForWorker(wp: { serviceCategories: string[] }): JobCategory[] {
  const cats = wp.serviceCategories as JobCategory[];
  return cats.length > 0 ? cats : ALL_JOB_CATEGORIES;
}

const router = Router();

const createJobSchema = z.object({
  category: z.nativeEnum(JobCategory),
  title: z.string().min(3),
  description: z.string().min(10),
  photos: z.array(z.string().url()).default([]),
  locationLat: z.number(),
  locationLng: z.number(),
  address: z.string(),
  scheduledAt: z.string().datetime().optional(),
});

router.post(
  "/",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = createJobSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const d = parsed.data;
    for (const field of [d.title, d.description, d.address] as const) {
      const check = validateNoContactInfo(field);
      if (!check.ok) {
        res.status(400).json({ error: check.message, code: "CONTACT_INFO_NOT_ALLOWED" });
        return;
      }
    }
    const job = await prisma.job.create({
      data: {
        customerId: req.user!.dbId,
        category: d.category,
        title: d.title,
        description: d.description,
        photos: d.photos,
        locationLat: d.locationLat,
        locationLng: d.locationLng,
        address: d.address,
        status: JobStatus.OPEN,
        firestoreThreadId: uuidv4(),
        scheduledAt: d.scheduledAt ? new Date(d.scheduledAt) : null,
      },
    });
    notifyNewJob(job.id, req.user!.dbId);
    res.status(201).json(job);
  }
);

router.get("/", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const user = await prisma.user.findUnique({ where: { id: req.user!.dbId } });
  if (!user) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  if (user.role === UserRole.CUSTOMER) {
    const jobs = await prisma.job.findMany({
      where: { customerId: user.id },
      orderBy: { createdAt: "desc" },
      include: {
        worker: { select: { id: true, name: true } },
      },
    });
    const ids = jobs.map((j) => j.id);
    const heldRows =
      ids.length > 0
        ? await prisma.transaction.findMany({
            where: {
              jobId: { in: ids },
              status: TransactionStatus.HELD,
            },
            select: { jobId: true },
          })
        : [];
    const heldSet = new Set(heldRows.map((r) => r.jobId));
    res.json({
      jobs: jobs.map((j) => ({
        ...j,
        escrowHeld: heldSet.has(j.id),
      })),
    });
    return;
  }
  if (user.role === UserRole.WORKER) {
    const wp = await prisma.workerProfile.findUnique({
      where: { userId: user.id },
    });
    if (!wp) {
      res.json({ jobs: [] });
      return;
    }
    const baseLat = wp.baseLocationLat ?? DEFAULT_BASE_LAT;
    const baseLng = wp.baseLocationLng ?? DEFAULT_BASE_LNG;
    const radiusKm = wp.serviceRadiusKm || MAX_QUOTE_KM;

    /** Jobs this worker is assigned to — not only OPEN (those vanish after accept). */
    const assignedToMe = await prisma.job.findMany({
      where: {
        workerId: user.id,
        status: {
          in: [
            JobStatus.ACCEPTED,
            JobStatus.IN_PROGRESS,
            JobStatus.COMPLETED,
            JobStatus.DISPUTED,
          ],
        },
      },
      include: {
        customer: { select: { id: true, name: true } },
      },
      orderBy: [{ quoteAcceptedAt: "desc" }, { createdAt: "desc" }],
      take: 80,
    });

    const openPool = await prisma.job.findMany({
      where: {
        status: JobStatus.OPEN,
        category: { in: categoriesForWorker(wp) },
      },
      include: {
        customer: { select: { id: true, name: true } },
      },
      orderBy: { createdAt: "desc" },
      take: 100,
    });
    const nearbyOpen = openPool.filter((j) => {
      return (
        distanceKm(baseLat, baseLng, j.locationLat, j.locationLng) <= radiusKm
      );
    });

    const seen = new Set<string>();
    const merged: (typeof assignedToMe)[number][] = [];
    for (const j of assignedToMe) {
      if (!seen.has(j.id)) {
        seen.add(j.id);
        merged.push(j);
      }
    }
    for (const j of nearbyOpen) {
      if (!seen.has(j.id)) {
        seen.add(j.id);
        merged.push(j);
      }
    }

    /** Latest PENDING / COUNTERED quote per OPEN job for this worker (for Jobs / Pending UI). */
    const pendingQuotesRaw = await prisma.quote.findMany({
      where: {
        workerId: user.id,
        status: { in: [QuoteStatus.PENDING, QuoteStatus.COUNTERED] },
        job: { status: JobStatus.OPEN },
      },
      orderBy: { updatedAt: "desc" },
    });
    const pendingByJobId = new Map<string, (typeof pendingQuotesRaw)[number]>();
    for (const q of pendingQuotesRaw) {
      if (!pendingByJobId.has(q.jobId)) pendingByJobId.set(q.jobId, q);
    }

    const mergedIds = new Set(merged.map((j) => j.id));
    const missingPendingIds = [...pendingByJobId.keys()].filter(
      (id) => !mergedIds.has(id),
    );
    if (missingPendingIds.length > 0) {
      const extra = await prisma.job.findMany({
        where: { id: { in: missingPendingIds }, status: JobStatus.OPEN },
        include: {
          customer: { select: { id: true, name: true } },
        },
      });
      for (const j of extra) {
        if (!mergedIds.has(j.id)) {
          mergedIds.add(j.id);
          merged.push(j);
        }
      }
    }

    const mergedIdsForEscrow = merged.map((j) => j.id);
    const heldForMerged =
      mergedIdsForEscrow.length > 0
        ? await prisma.transaction.findMany({
            where: {
              jobId: { in: mergedIdsForEscrow },
              status: TransactionStatus.HELD,
            },
            select: { jobId: true },
          })
        : [];
    const escrowHeldJobIds = new Set(heldForMerged.map((r) => r.jobId));

    const jobsPayload = merged.map((j) => {
      const pq = pendingByJobId.get(j.id);
      return {
        ...j,
        escrowHeld: escrowHeldJobIds.has(j.id),
        pendingQuote: pq
          ? {
              status: pq.status,
              amountPesewas: pq.amountPesewas,
              counterAmountPesewas: pq.counterAmountPesewas,
              expiresAt: pq.expiresAt.toISOString(),
            }
          : null,
      };
    });
    res.json({ jobs: jobsPayload });
    return;
  }
  res.json({ jobs: [] });
});

router.get("/available", authMiddleware([UserRole.WORKER]), async (req: AuthedRequest, res: Response) => {
  const wp = await prisma.workerProfile.findUnique({
    where: { userId: req.user!.dbId },
  });
  if (!wp) {
    res.json({ jobs: [] });
    return;
  }
  const baseLat = wp.baseLocationLat ?? DEFAULT_BASE_LAT;
  const baseLng = wp.baseLocationLng ?? DEFAULT_BASE_LNG;
  const radiusKm = wp.serviceRadiusKm || MAX_QUOTE_KM;
  const jobs = await prisma.job.findMany({
    where: {
      status: JobStatus.OPEN,
      category: { in: categoriesForWorker(wp) },
    },
    orderBy: { createdAt: "desc" },
  });
  const nearby = jobs.filter(
    (j) =>
      distanceKm(baseLat, baseLng, j.locationLat, j.locationLng) <= radiusKm
  );
  res.json({ jobs: nearby });
});

router.get("/:id", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const job = await prisma.job.findUnique({
    where: { id: param(req, "id") },
    include: {
      customer: {
        select: { id: true, name: true, profilePhoto: true, phone: true },
      },
      worker: { include: { workerProfile: true } },
    },
  });
  if (!job) {
    res.status(404).json({ error: "Not found" });
    return;
  }
  const uid = req.user!.dbId;
  const viewer = req.user!;
  const canViewAsWorker =
    viewer.role === UserRole.WORKER &&
    job.status === JobStatus.OPEN &&
    job.customerId !== uid;
  if (
    job.customerId !== uid &&
    job.workerId !== uid &&
    viewer.role !== UserRole.ADMIN &&
    !canViewAsWorker
  ) {
    res.status(403).json({ error: "Forbidden" });
    return;
  }
  let workerPayload = null;
  if (job.worker) {
    workerPayload = serializeWorkerPublic(job.worker, {
      jobStatus: job.status as JobStatus,
      viewerIsCustomer: job.customerId === uid,
    });
  }

  let acceptedQuote: {
    id: string;
    amountPesewas: number;
    breakdown: unknown;
    message: string | null;
    counterAmountPesewas: number | null;
  } | null = null;
  if (
    job.customerId === uid ||
    (viewer.role === UserRole.WORKER && job.workerId === uid)
  ) {
    const aq = await prisma.quote.findFirst({
      where: { jobId: job.id, status: QuoteStatus.ACCEPTED },
      orderBy: { updatedAt: "desc" },
    });
    if (aq) {
      acceptedQuote = {
        id: aq.id,
        amountPesewas: aq.amountPesewas,
        breakdown: aq.breakdown,
        message: aq.message,
        counterAmountPesewas: aq.counterAmountPesewas,
      };
    }
  }

  const heldEscrow = await prisma.transaction.findFirst({
    where: { jobId: job.id, status: TransactionStatus.HELD },
    select: { id: true },
  });

  /** Worker's active quote on this OPEN job (pending or countered) — drives “awaiting confirmation” in worker app. */
  let myQuote: {
    id: string;
    status: QuoteStatus;
    amountPesewas: number;
    counterAmountPesewas: number | null;
    expiresAt: string | null;
  } | null = null;
  if (viewer.role === UserRole.WORKER && job.customerId !== uid) {
    const mq = await prisma.quote.findFirst({
      where: {
        jobId: job.id,
        workerId: uid,
        status: { in: [QuoteStatus.PENDING, QuoteStatus.COUNTERED] },
      },
      orderBy: { updatedAt: "desc" },
    });
    if (mq) {
      myQuote = {
        id: mq.id,
        status: mq.status,
        amountPesewas: mq.amountPesewas,
        counterAmountPesewas: mq.counterAmountPesewas,
        expiresAt: mq.expiresAt?.toISOString() ?? null,
      };
    }
  }

  res.json({
    ...job,
    worker: workerPayload,
    acceptedQuote,
    /** True while customer funds are in escrow (`TransactionStatus.HELD`). Worker can only request completion when this is true. */
    escrowHeld: heldEscrow != null,
    myQuote,
  });
});

/** Worker signals work is finished; customer must confirm via `POST /payments/release/:jobId`. */
router.post(
  "/:id/request-completion",
  authMiddleware([UserRole.WORKER]),
  async (req: AuthedRequest, res: Response) => {
    const job = await prisma.job.findUnique({ where: { id: param(req, "id") } });
    if (!job) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    if (job.workerId !== req.user!.dbId) {
      res.status(403).json({ error: "You are not assigned to this job" });
      return;
    }
    if (job.status !== JobStatus.ACCEPTED && job.status !== JobStatus.IN_PROGRESS) {
      res.status(400).json({ error: "Job must be accepted or in progress" });
      return;
    }
    const held = await prisma.transaction.findFirst({
      where: { jobId: job.id, status: TransactionStatus.HELD },
    });
    if (!held) {
      res.status(400).json({
        error: "Payment must be held in escrow before the job can be marked done",
      });
      return;
    }
    if (job.workerRequestedCompletionAt) {
      const fresh = await prisma.job.findUnique({ where: { id: job.id } });
      res.json({ ok: true, job: fresh });
      return;
    }
    const updated = await prisma.job.update({
      where: { id: job.id },
      data: { workerRequestedCompletionAt: new Date() },
    });
    void notifyJobChange(job.id, "worker_requested_completion");
    res.json({ ok: true, job: updated });
  }
);

const statusSchema = z.object({
  status: z.nativeEnum(JobStatus),
});

router.put(
  "/:id/status",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = statusSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const job = await prisma.job.findUnique({ where: { id: param(req, "id") } });
    if (!job) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const next = parsed.data.status;

    if (next === JobStatus.COMPLETED) {
      res.status(400).json({
        error:
          "Completion is confirmed by the customer when they release payment, after you tap ‘work done’.",
      });
      return;
    }

    if (next === JobStatus.IN_PROGRESS) {
      if (job.workerId !== req.user!.dbId && req.user!.role !== UserRole.ADMIN) {
        res.status(403).json({ error: "Only the assigned worker can mark the job as in progress" });
        return;
      }
      const held = await prisma.transaction.findFirst({
        where: { jobId: job.id, status: TransactionStatus.HELD },
      });
      if (!held) {
        res.status(400).json({
          error: "Payment must be held in escrow before starting work",
        });
        return;
      }
    }

    const updated = await prisma.job.update({
      where: { id: job.id },
      data: { status: next },
    });
    void notifyJobChange(job.id, "status");
    res.json(updated);
  }
);

router.delete(
  "/:id",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const job = await prisma.job.findUnique({ where: { id: param(req, "id") } });
    if (!job || job.customerId !== req.user!.dbId) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const paid = await prisma.transaction.findFirst({
      where: { jobId: job.id, status: { in: ["HELD", "RELEASED"] } },
    });
    if (paid) {
      res.status(400).json({ error: "Cannot cancel after payment" });
      return;
    }
    await prisma.job.update({
      where: { id: job.id },
      data: { status: JobStatus.CANCELLED },
    });
    void notifyJobChange(job.id, "cancelled");
    res.status(204).send();
  }
);

router.post(
  "/:id/photos",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z.object({ urls: z.array(z.string().url()).max(10) }).safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const job = await prisma.job.findFirst({
      where: { id: param(req, "id"), customerId: req.user!.dbId },
    });
    if (!job) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const updated = await prisma.job.update({
      where: { id: job.id },
      data: { photos: [...job.photos, ...parsed.data.urls] },
    });
    void notifyJobChange(job.id, "photos");
    res.json(updated);
  }
);

const quoteBody = z.object({
  amountPesewas: z.number().int().positive(),
  breakdown: z
    .object({
      labour: z.number().optional(),
      parts: z.number().optional(),
      transport: z.number().optional(),
    })
    .optional(),
  message: z.string().optional(),
});

router.post(
  "/:id/quotes",
  authMiddleware([UserRole.WORKER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = quoteBody.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const job = await prisma.job.findUnique({ where: { id: param(req, "id") } });
    if (!job || job.status !== JobStatus.OPEN) {
      res.status(400).json({ error: "Job not open for quotes" });
      return;
    }
    const wp = await prisma.workerProfile.findUnique({
      where: { userId: req.user!.dbId },
    });
    if (!wp) {
      res.status(400).json({ error: "Worker profile missing" });
      return;
    }
    const baseLat = wp.baseLocationLat ?? DEFAULT_BASE_LAT;
    const baseLng = wp.baseLocationLng ?? DEFAULT_BASE_LNG;
    const workerCats = categoriesForWorker(wp);
    if (
      !workerCats.includes(job.category) &&
      job.category !== JobCategory.OTHER
    ) {
      res.status(400).json({ error: "Not your category" });
      return;
    }
    const dist = distanceKm(
      baseLat,
      baseLng,
      job.locationLat,
      job.locationLng
    );
    if (dist > MAX_QUOTE_KM) {
      res.status(400).json({ error: `Job is more than ${MAX_QUOTE_KM}km away` });
      return;
    }
    const existing = await prisma.quote.findMany({
      where: { jobId: job.id, workerId: req.user!.dbId },
    });
    if (existing.some((q) => q.status === QuoteStatus.PENDING || q.status === QuoteStatus.COUNTERED)) {
      res.status(400).json({ error: "You already have an active quote on this job" });
      return;
    }
    const count = await prisma.quote.count({
      where: {
        jobId: job.id,
        status: { in: [QuoteStatus.PENDING, QuoteStatus.COUNTERED] },
      },
    });
    if (count >= MAX_QUOTES) {
      res.status(400).json({ error: "Maximum quotes reached for this job" });
      return;
    }
    const msg = parsed.data.message?.trim();
    if (msg) {
      const check = validateNoContactInfo(msg);
      if (!check.ok) {
        res.status(400).json({ error: check.message, code: "CONTACT_INFO_NOT_ALLOWED" });
        return;
      }
    }
    const expiresAt = new Date(Date.now() + QUOTE_EXPIRY_MS);
    const quote = await prisma.quote.create({
      data: {
        jobId: job.id,
        workerId: req.user!.dbId,
        amountPesewas: parsed.data.amountPesewas,
        breakdown: parsed.data.breakdown ?? undefined,
        message: msg && msg.length > 0 ? msg : undefined,
        status: QuoteStatus.PENDING,
        expiresAt,
      },
    });
    // Keep job OPEN until a quote is accepted; multiple workers can still quote.
    void notifyJobChange(job.id, "quote");
    res.status(201).json(quote);
  }
);

router.get(
  "/:id/quotes",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const job = await prisma.job.findUnique({ where: { id: param(req, "id") } });
    if (!job) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const uid = req.user!.dbId;
    const preQuotes = await prisma.quote.findMany({ where: { jobId: job.id } });
    const canViewQuotes =
      job.customerId === uid ||
      job.workerId === uid ||
      preQuotes.some((q) => q.workerId === uid) ||
      req.user!.role === UserRole.ADMIN;
    if (!canViewQuotes) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
    const quotes = await prisma.quote.findMany({
      where: { jobId: job.id },
      include: { worker: { include: { workerProfile: true } } },
    });
    const viewerIsCustomer = job.customerId === uid;
    res.json({
      quotes: quotes.map((q) => ({
        ...q,
        worker: serializeWorkerPublic(q.worker, {
          jobStatus: job.status as JobStatus,
          viewerIsCustomer,
          revealFullName: viewerIsCustomer,
        }),
      })),
    });
  }
);

export default router;
