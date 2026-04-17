import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import { BackgroundCheckStatus, UserRole } from "@prisma/client";
import { serializeWorkerPublic } from "../services/workerSerialize";
import { distanceKm } from "../utils/geo";
import { param } from "../utils/params";

const router = Router();

router.get("/", async (req, res) => {
  const q = z
    .object({
      category: z.string().optional(),
      minRating: z.coerce.number().optional(),
      lat: z.coerce.number().optional(),
      lng: z.coerce.number().optional(),
      radiusKm: z.coerce.number().optional().default(50),
    })
    .safeParse(req.query);
  if (!q.success) {
    res.status(400).json({ error: q.error.flatten() });
    return;
  }
  const workers = await prisma.user.findMany({
    where: {
      role: UserRole.WORKER,
      isActive: true,
      isSuspended: false,
      workerProfile: {
        is: {
          backgroundCheckStatus: BackgroundCheckStatus.APPROVED,
          ...(q.data.category
            ? { serviceCategories: { has: q.data.category } }
            : {}),
          ...(q.data.minRating != null
            ? { rating: { gte: q.data.minRating } }
            : {}),
        },
      },
    },
    include: { workerProfile: true },
    take: 50,
  });
  const list = workers.map((u) =>
    serializeWorkerPublic(u, { jobStatus: null, viewerIsCustomer: true })
  );
  if (q.data.lat != null && q.data.lng != null) {
    const filtered = list.filter((_, i) => {
      const w = workers[i].workerProfile;
      if (!w?.baseLocationLat || !w?.baseLocationLng) return false;
      return (
        distanceKm(
          q.data.lat!,
          q.data.lng!,
          w.baseLocationLat,
          w.baseLocationLng
        ) <= q.data.radiusKm
      );
    });
    res.json({ workers: filtered });
    return;
  }
  res.json({ workers: list });
});

router.get("/nearby", async (req, res) => {
  const q = z
    .object({
      lat: z.coerce.number(),
      lng: z.coerce.number(),
      radiusKm: z.coerce.number().default(20),
    })
    .safeParse(req.query);
  if (!q.success) {
    res.status(400).json({ error: q.error.flatten() });
    return;
  }
  const workers = await prisma.user.findMany({
    where: {
      role: UserRole.WORKER,
      isActive: true,
      workerProfile: {
        is: { backgroundCheckStatus: BackgroundCheckStatus.APPROVED },
      },
    },
    include: { workerProfile: true },
  });
  const out = workers.filter((u) => {
    const w = u.workerProfile;
    if (!w?.baseLocationLat || !w?.baseLocationLng) return false;
    return (
      distanceKm(
        q.data.lat,
        q.data.lng,
        w.baseLocationLat,
        w.baseLocationLng
      ) <= q.data.radiusKm
    );
  });
  res.json({
    workers: out.map((u) =>
      serializeWorkerPublic(u, { jobStatus: null, viewerIsCustomer: true })
    ),
  });
});

router.get("/:id", async (req, res) => {
  const user = await prisma.user.findFirst({
    where: {
      id: param(req, "id"),
      role: UserRole.WORKER,
      workerProfile: {
        is: { backgroundCheckStatus: BackgroundCheckStatus.APPROVED },
      },
    },
    include: { workerProfile: true },
  });
  if (!user?.workerProfile) {
    res.status(404).json({ error: "Worker not found" });
    return;
  }
  res.json(
    serializeWorkerPublic(user, { jobStatus: null, viewerIsCustomer: true })
  );
});

router.put(
  "/profile",
  authMiddleware([UserRole.WORKER]),
  async (req: AuthedRequest, res: Response) => {
    const schema = z.object({
      bio: z.string().optional(),
      serviceCategories: z.array(z.string()).optional(),
      baseLocationLat: z.number().optional(),
      baseLocationLng: z.number().optional(),
      serviceRadiusKm: z.number().optional(),
      momoNumber: z.string().optional(),
      momoProvider: z.enum(["MTN", "TELECEL", "AIRTELTIGO", "OTHER"]).optional(),
      bankAccountNumber: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const wp = await prisma.workerProfile.update({
      where: { userId: req.user!.dbId },
      data: parsed.data,
      include: { user: true },
    });
    res.json(wp);
  }
);

router.post(
  "/documents",
  authMiddleware([UserRole.WORKER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z.object({ idDocumentUrl: z.string().url() }).safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const wp = await prisma.workerProfile.update({
      where: { userId: req.user!.dbId },
      data: { idDocumentUrl: parsed.data.idDocumentUrl },
    });
    res.json(wp);
  }
);

router.get("/:id/reviews", async (req, res) => {
  const reviews = await prisma.review.findMany({
    where: { revieweeId: param(req, "id") },
    orderBy: { createdAt: "desc" },
    take: 50,
    include: { reviewer: { select: { id: true, name: true, profilePhoto: true } } },
  });
  res.json({ reviews });
});

export default router;
