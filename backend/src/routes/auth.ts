import { Router } from "express";
import type { Response } from "express";
import { ALL_JOB_CATEGORIES } from "../constants/jobCategories";
import { prisma } from "../lib/prisma";
import { hashPassword, verifyPassword } from "../utils/password";
import {
  signAccess,
  signRefresh,
  verifyRefresh,
} from "../utils/jwt";
import {
  loginSchema,
  refreshSchema,
  registerSchema,
  verifyPhoneSchema,
  requestOtpSchema,
} from "../validation/schemas";
import type { AuthedRequest } from "../middleware/auth";
import { authMiddleware } from "../middleware/auth";
import { randomInt } from "crypto";

const router = Router();

function normalizeRegisterBody(body: unknown): unknown {
  if (!body || typeof body !== "object") return body;
  const b = body as Record<string, unknown>;
  return {
    ...b,
    name: typeof b.name === "string" ? b.name.trim() : b.name,
    email: typeof b.email === "string" ? b.email.trim().toLowerCase() : b.email,
    phone:
      typeof b.phone === "string"
        ? b.phone.replace(/[\s\-.]/g, "")
        : b.phone,
    password:
      typeof b.password === "string" ? b.password.trim() : b.password,
    role: b.role,
  };
}

router.post("/register", async (req, res) => {
  const parsed = registerSchema.safeParse(normalizeRegisterBody(req.body));
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const { name, email, phone, password, role } = parsed.data;
  const existing = await prisma.user.findFirst({
    where: { OR: [{ email }, { phone }] },
  });
  if (existing) {
    res.status(409).json({ error: "Email or phone already registered" });
    return;
  }
  const passwordHash = await hashPassword(password);
  const user = await prisma.user.create({
    data: {
      name,
      email,
      phone,
      passwordHash,
      role,
      ...(role === "WORKER"
        ? {
            workerProfile: {
              create: {
                serviceCategories: [...ALL_JOB_CATEGORIES],
                baseLocationLat: 5.6037,
                baseLocationLng: -0.187,
              },
            },
          }
        : {}),
    },
  });
  const payload = { sub: user.id, role: user.role };
  const accessToken = signAccess(payload);
  const refreshRaw = signRefresh(payload);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await prisma.refreshToken.create({
    data: { token: refreshRaw, userId: user.id, expiresAt },
  });
  res.status(201).json({
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
    },
    accessToken,
    refreshToken: refreshRaw,
  });
});

router.post("/login", async (req, res) => {
  const raw = req.body as Record<string, unknown> | undefined;
  const parsed = loginSchema.safeParse({
    email: typeof raw?.email === "string" ? raw.email.trim().toLowerCase() : raw?.email,
    password:
      typeof raw?.password === "string" ? raw.password.trim() : raw?.password,
  });
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const { email, password } = parsed.data;
  const user = await prisma.user.findFirst({
    where: {
      email: {
        equals: email,
        mode: "insensitive",
      },
    },
  });
  if (!user || !(await verifyPassword(password, user.passwordHash))) {
    res.status(401).json({ error: "Invalid credentials" });
    return;
  }
  if (user.isSuspended || !user.isActive) {
    res.status(403).json({ error: "Account disabled" });
    return;
  }
  const payload = { sub: user.id, role: user.role };
  const accessToken = signAccess(payload);
  const refreshRaw = signRefresh(payload);
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await prisma.refreshToken.create({
    data: { token: refreshRaw, userId: user.id, expiresAt },
  });
  res.json({
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
    },
    accessToken,
    refreshToken: refreshRaw,
  });
});

router.post("/refresh", async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  try {
    const payload = verifyRefresh(parsed.data.refreshToken);
    const stored = await prisma.refreshToken.findUnique({
      where: { token: parsed.data.refreshToken },
    });
    if (!stored || stored.expiresAt < new Date()) {
      res.status(401).json({ error: "Invalid refresh token" });
      return;
    }
    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user) {
      res.status(401).json({ error: "Invalid refresh token" });
      return;
    }
    const nextPayload = { sub: user.id, role: user.role };
    const accessToken = signAccess(nextPayload);
    res.json({ accessToken });
  } catch {
    res.status(401).json({ error: "Invalid refresh token" });
  }
});

router.post(
  "/logout",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const parsed = refreshSchema.safeParse(req.body);
    if (parsed.success) {
      await prisma.refreshToken.deleteMany({
        where: { token: parsed.data.refreshToken },
      });
    }
    res.status(204).send();
  }
);

/** Request OTP — stores 6-digit code (SMS integration via Africa's Talking in production) */
router.post("/request-otp", async (req, res) => {
  const parsed = requestOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const code = String(randomInt(100000, 999999));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
  await prisma.otpCode.deleteMany({ where: { phone: parsed.data.phone } });
  await prisma.otpCode.create({
    data: { phone: parsed.data.phone, code, expiresAt },
  });
  if (process.env.NODE_ENV === "development") {
    res.json({ ok: true, devCode: code });
    return;
  }
  res.json({ ok: true });
});

router.post("/verify-phone", async (req, res) => {
  const parsed = verifyPhoneSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  const { phone, code } = parsed.data;
  const otp = await prisma.otpCode.findFirst({
    where: { phone, code, expiresAt: { gt: new Date() } },
    orderBy: { createdAt: "desc" },
  });
  if (!otp) {
    res.status(400).json({ error: "Invalid or expired code" });
    return;
  }
  await prisma.user.updateMany({
    where: { phone },
    data: { isVerified: true },
  });
  await prisma.otpCode.deleteMany({ where: { phone } });
  res.json({ ok: true });
});

export default router;
