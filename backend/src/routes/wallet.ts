import { Router } from "express";
import { z } from "zod";
import type { Response } from "express";
import {
  WalletLedgerType,
  UserRole,
  WalletLedgerDirection,
} from "@prisma/client";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import {
  creditWalletLedger,
  debitWalletLedger,
  getOrCreateWallet,
  sumCustomerEscrowHeldPesewas,
} from "../services/wallet";

const router = Router();

/** Worker-facing credits that count as earned income (not wallet top-ups). */
const WORKER_EARNINGS_LEDGER_TYPES: WalletLedgerType[] = [
  WalletLedgerType.JOB_PAYMENT,
  WalletLedgerType.TIP,
  WalletLedgerType.ADMIN_CREDIT,
  WalletLedgerType.ESCROW_RELEASE,
];

function startOfWeekMondayUtc(d = new Date()): Date {
  const x = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
  );
  const dow = x.getUTCDay();
  const daysFromMon = dow === 0 ? 6 : dow - 1;
  x.setUTCDate(x.getUTCDate() - daysFromMon);
  x.setUTCHours(0, 0, 0, 0);
  return x;
}

function startOfMonthUtc(d = new Date()): Date {
  return new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1, 0, 0, 0, 0)
  );
}

function startOfTodayUtc(d = new Date()): Date {
  return new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0, 0)
  );
}

async function sumWorkerEarningsSince(
  walletId: string,
  since: Date
): Promise<number> {
  const agg = await prisma.walletLedgerEntry.aggregate({
    where: {
      walletId,
      direction: WalletLedgerDirection.CREDIT,
      type: { in: WORKER_EARNINGS_LEDGER_TYPES },
      createdAt: { gte: since },
    },
    _sum: { amountPesewas: true },
  });
  return agg._sum.amountPesewas ?? 0;
}

function isDevWalletTopupSimulate(): boolean {
  return (
    process.env.NODE_ENV === "development" &&
    (process.env.DEV_SIMULATE_WALLET_TOPUP === "true" ||
      process.env.DEV_SIMULATE_ESCROW === "true")
  );
}

router.get("/", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const userId = req.user!.dbId;
  const wallet = await getOrCreateWallet(userId);
  let inEscrowPesewas = 0;
  if (req.user!.role === UserRole.CUSTOMER) {
    inEscrowPesewas = await sumCustomerEscrowHeldPesewas(userId);
  }
  const weekStart = startOfWeekMondayUtc();
  const monthStart = startOfMonthUtc();
  const todayStart = startOfTodayUtc();
  const [recent, earningsToday, earningsWeek, earningsMonth] = await Promise.all([
    prisma.walletLedgerEntry.findMany({
      where: { walletId: wallet.id },
      orderBy: { createdAt: "desc" },
      take: 100,
    }),
    req.user!.role === UserRole.WORKER
      ? sumWorkerEarningsSince(wallet.id, todayStart)
      : Promise.resolve(0),
    req.user!.role === UserRole.WORKER
      ? sumWorkerEarningsSince(wallet.id, weekStart)
      : Promise.resolve(0),
    req.user!.role === UserRole.WORKER
      ? sumWorkerEarningsSince(wallet.id, monthStart)
      : Promise.resolve(0),
  ]);
  res.json({
    balancePesewas: wallet.balancePesewas,
    inEscrowPesewas,
    isLocked: wallet.isLocked,
    /** Sum of worker income credits since UTC midnight today. Workers only. */
    earningsTodayPesewas: earningsToday,
    /** Sum of job payouts & tips credited this calendar week (UTC Monday start). Workers only. */
    earningsThisWeekPesewas: earningsWeek,
    /** Sum credited this calendar month (UTC). Workers only. */
    earningsThisMonthPesewas: earningsMonth,
    recent,
  });
});

const topupSchema = z.object({
  /** Min GHS 10, max GHS 5000 (spec) */
  amountPesewas: z.number().int().min(1000).max(500000),
});

/** Minimum GHS 10 = 1000 pesewas; max GHS 5000 = 50000000 — spec limits */
router.post(
  "/topup",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = topupSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const { amountPesewas } = parsed.data;
    const userId = req.user!.dbId;

    if (!isDevWalletTopupSimulate()) {
      res.status(501).json({
        error:
          "Wallet top-up via Paystack is not wired in this build. Enable DEV_SIMULATE_ESCROW or DEV_SIMULATE_WALLET_TOPUP in development, or use Admin → Wallet credit for test funds.",
      });
      return;
    }

    await prisma.$transaction(async (tx) => {
      await creditWalletLedger(
        tx,
        userId,
        amountPesewas,
        WalletLedgerType.TOPUP,
        "Test top-up (simulated)",
        { reference: `topup_sim_${Date.now()}` }
      );
    });

    const wallet = await getOrCreateWallet(userId);
    res.status(201).json({
      ok: true,
      balancePesewas: wallet.balancePesewas,
      devSimulated: true,
    });
  }
);

const withdrawSchema = z.object({
  amountPesewas: z.number().int().min(2000),
  momoNumber: z.string().min(9),
  momoProvider: z.enum(["MTN", "TELECEL", "AIRTELTIGO", "OTHER"]),
});

router.post(
  "/withdraw",
  authMiddleware([UserRole.WORKER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = withdrawSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const { amountPesewas, momoNumber, momoProvider } = parsed.data;
    const userId = req.user!.dbId;

    await prisma.$transaction(async (tx) => {
      await debitWalletLedger(
        tx,
        userId,
        amountPesewas,
        WalletLedgerType.WITHDRAWAL,
        `Withdrawal to MoMo ${momoProvider} ${momoNumber}`,
        { reference: `wd_${Date.now()}` }
      );
    });

    const w = await getOrCreateWallet(userId);
    res.json({
      ok: true,
      message:
        "Payout queued (demo). Connect Paystack Transfer API for production instant payouts.",
      balancePesewas: w.balancePesewas,
    });
  }
);

export default router;
