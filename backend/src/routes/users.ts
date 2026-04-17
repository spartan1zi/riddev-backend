import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";

const router = Router();

function userPublicJson(user: {
  passwordHash: string;
  fcmToken?: string | null;
  [key: string]: unknown;
}) {
  const { passwordHash: _, fcmToken: __, ...rest } = user;
  return rest;
}

const updateMeSchema = z.object({
  name: z.string().min(2).optional(),
  profilePhoto: z.string().url().optional().nullable(),
  locationLat: z.number().optional().nullable(),
  locationLng: z.number().optional().nullable(),
});

router.get("/me", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const user = await prisma.user.findUnique({
    where: { id: req.user!.dbId },
    include: { workerProfile: true },
  });
  if (!user) {
    res.status(404).json({ error: "Not found" });
    return;
  }
  res.json(userPublicJson(user));
});

router.post(
  "/me/fcm-token",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        /** FCM registration token; send null to clear. */
        token: z.string().min(10).max(4096).nullable(),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    await prisma.user.update({
      where: { id: req.user!.dbId },
      data: { fcmToken: parsed.data.token },
    });
    res.json({ ok: true });
  }
);

router.put("/me", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const parsed = updateMeSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const user = await prisma.user.update({
    where: { id: req.user!.dbId },
    data: parsed.data,
  });
  res.json(userPublicJson(user));
});

router.post(
  "/me/photo",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const body = z.object({ url: z.string().url() }).safeParse(req.body);
    if (!body.success) {
      res.status(400).json({ error: body.error.flatten() });
      return;
    }
    const user = await prisma.user.update({
      where: { id: req.user!.dbId },
      data: { profilePhoto: body.data.url },
    });
    res.json(userPublicJson(user));
  }
);

router.delete("/me", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  await prisma.user.update({
    where: { id: req.user!.dbId },
    data: { isActive: false },
  });
  res.status(204).send();
});

export default router;
