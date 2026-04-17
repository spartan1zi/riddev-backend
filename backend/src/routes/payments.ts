import { Router } from "express";
import { z } from "zod";
import type { Response, Request } from "express";
import { authMiddleware, type AuthedRequest } from "../middleware/auth";
import { prisma } from "../lib/prisma";
import { JobStatus, TransactionStatus, UserRole, WalletLedgerType } from "@prisma/client";
import { notifyJobChange } from "../lib/realtime";
import { verifyPaystackSignature } from "../lib/paystack";
import { computeFees } from "../utils/pricing";
import { param } from "../utils/params";
import { creditWalletLedger, debitWalletLedger } from "../services/wallet";

const router = Router();

/** When `NODE_ENV=development` and `DEV_SIMULATE_ESCROW=true`, skip Paystack and mark the txn HELD immediately (testing only). */
function isDevSimulateEscrow(): boolean {
  return (
    process.env.NODE_ENV === "development" && process.env.DEV_SIMULATE_ESCROW === "true"
  );
}

router.post(
  "/initiate",
  authMiddleware([UserRole.CUSTOMER]),
  async (req: AuthedRequest, res: Response) => {
    const parsed = z
      .object({
        jobId: z.string().uuid(),
        /** Pay with in-app wallet balance, or external Paystack / MoMo flow. */
        fundingSource: z.enum(["PAYSTACK", "WALLET"]).default("PAYSTACK"),
        momoNumber: z.string().optional(),
        momoProvider: z.enum(["MTN", "TELECEL", "AIRTELTIGO", "OTHER"]).optional(),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }
    const job = await prisma.job.findFirst({
      where: {
        id: parsed.data.jobId,
        customerId: req.user!.dbId,
        status: JobStatus.ACCEPTED,
      },
      include: { worker: { include: { workerProfile: true } } },
    });
    if (!job || !job.workerId || !job.agreedPricePesewas) {
      res.status(400).json({ error: "Job not ready for payment" });
      return;
    }

    const simulateEscrow = isDevSimulateEscrow();

    const existingHeld = await prisma.transaction.findFirst({
      where: { jobId: job.id, status: TransactionStatus.HELD },
    });
    if (existingHeld) {
      res.json({
        reference: existingHeld.paystackReference,
        amountPesewas: existingHeld.amountPesewas,
        publicKey: process.env.PAYSTACK_PUBLIC_KEY ?? "",
        transactionId: existingHeld.id,
        authorizationUrl: simulateEscrow ? "" : `https://paystack.com/pay/${existingHeld.paystackReference}`,
        devSimulatedEscrow: simulateEscrow,
      });
      return;
    }

    const bps = job.worker?.workerProfile?.commissionRateBps ?? 1500;
    const fees = computeFees(job.agreedPricePesewas, bps);
    const totalCustomerPays = fees.customerTotalPesewas;

    if (parsed.data.fundingSource === "WALLET") {
      const ref = `wallet_${job.id}_${Date.now()}`;
      let txnId: string;
      try {
        txnId = await prisma.$transaction(async (txc) => {
        await debitWalletLedger(
          txc,
          job.customerId,
          totalCustomerPays,
          WalletLedgerType.ESCROW_HOLD,
          `Escrow for job: ${job.title}`,
          { jobId: job.id, reference: ref }
        );
        const txn = await txc.transaction.create({
          data: {
            jobId: job.id,
            customerId: job.customerId,
            workerId: job.workerId!,
            paystackReference: ref,
            amountPesewas: totalCustomerPays,
            platformFeePesewas: fees.platformFeePesewas + fees.trustFeePesewas,
            workerAmountPesewas: fees.workerPayoutPesewas,
            status: TransactionStatus.HELD,
            momoNumber: parsed.data.momoNumber,
            momoProvider: parsed.data.momoProvider,
          },
        });
        await txc.job.update({
          where: { id: job.id },
          data: { paymentInitiatedAt: new Date() },
        });
        return txn.id;
      });
      } catch (e) {
        const msg = e instanceof Error ? e.message : "Wallet payment failed";
        res.status(400).json({ error: msg });
        return;
      }
      void notifyJobChange(job.id, "escrow_held");
      res.json({
        reference: ref,
        amountPesewas: totalCustomerPays,
        publicKey: process.env.PAYSTACK_PUBLIC_KEY ?? "",
        transactionId: txnId!,
        authorizationUrl: "",
        devSimulatedEscrow: false,
        fundedByWallet: true,
      });
      return;
    }

    const ref = `rd_${job.id}_${Date.now()}`;
    const txn = await prisma.transaction.create({
      data: {
        jobId: job.id,
        customerId: job.customerId,
        workerId: job.workerId,
        paystackReference: ref,
        amountPesewas: totalCustomerPays,
        platformFeePesewas: fees.platformFeePesewas + fees.trustFeePesewas,
        workerAmountPesewas: fees.workerPayoutPesewas,
        status: TransactionStatus.PENDING,
        momoNumber: parsed.data.momoNumber,
        momoProvider: parsed.data.momoProvider,
      },
    });
    await prisma.job.update({
      where: { id: job.id },
      data: { paymentInitiatedAt: new Date() },
    });

    if (simulateEscrow) {
      await prisma.transaction.update({
        where: { id: txn.id },
        data: { status: TransactionStatus.HELD },
      });
      void notifyJobChange(job.id, "escrow_held");
    }

    res.json({
      reference: ref,
      amountPesewas: totalCustomerPays,
      publicKey: process.env.PAYSTACK_PUBLIC_KEY ?? "",
      transactionId: txn.id,
      authorizationUrl: simulateEscrow ? "" : `https://paystack.com/pay/${ref}`,
      devSimulatedEscrow: simulateEscrow,
      fundedByWallet: false,
    });
  }
);

/** Raw body required for signature — mount with express.raw in index */
export function paystackWebhookHandler(req: Request, res: Response) {
  const sig = req.headers["x-paystack-signature"] as string | undefined;
  const rawBody = Buffer.isBuffer(req.body)
    ? req.body.toString("utf8")
    : typeof req.body === "string"
      ? req.body
      : JSON.stringify(req.body ?? {});
  if (!verifyPaystackSignature(rawBody, sig)) {
    res.status(400).send("invalid signature");
    return;
  }
  let payload: { event?: string; data?: { reference?: string; status?: string } };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    res.status(400).send("bad json");
    return;
  }
  if (payload.event === "charge.success" && payload.data?.reference) {
    void prisma.transaction
      .updateMany({
        where: { paystackReference: payload.data.reference },
        data: { status: TransactionStatus.HELD },
      })
      .then(() => res.sendStatus(200));
    return;
  }
  res.sendStatus(200);
}

router.post(
  "/release/:jobId",
  authMiddleware(),
  async (req: AuthedRequest, res: Response) => {
    const job = await prisma.job.findUnique({ where: { id: param(req, "jobId") } });
    if (!job) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    const uid = req.user!.dbId;
    if (job.customerId !== uid && req.user!.role !== UserRole.ADMIN) {
      res.status(403).json({ error: "Only the customer can confirm completion and release payment" });
      return;
    }
    if (!job.workerRequestedCompletionAt) {
      res.status(400).json({
        error:
          "The worker must mark the job as done first. Ask them to tap ‘work done’ in the worker app.",
      });
      return;
    }
    if (job.status === JobStatus.COMPLETED) {
      res.status(400).json({ error: "Job is already completed" });
      return;
    }
    const txn = await prisma.transaction.findFirst({
      where: { jobId: job.id, status: TransactionStatus.HELD },
    });
    if (!txn) {
      res.status(400).json({ error: "No held transaction" });
      return;
    }
    await prisma.$transaction(async (tx) => {
      await tx.transaction.update({
        where: { id: txn.id },
        data: { status: TransactionStatus.RELEASED, releasedAt: new Date() },
      });
      await tx.job.update({
        where: { id: job.id },
        data: { status: JobStatus.COMPLETED, completedAt: new Date() },
      });
      if (job.workerId && job.status !== JobStatus.COMPLETED) {
        await tx.workerProfile.update({
          where: { userId: job.workerId },
          data: { totalJobsCompleted: { increment: 1 } },
        });
        await creditWalletLedger(
          tx,
          job.workerId,
          txn.workerAmountPesewas,
          WalletLedgerType.JOB_PAYMENT,
          `Earnings from job: ${job.title}`,
          { jobId: job.id, reference: txn.id }
        );
      }
    });
    void notifyJobChange(job.id, "completed");
    res.json({ ok: true });
  }
);

router.post(
  "/refund/:jobId",
  authMiddleware([UserRole.ADMIN]),
  async (req: AuthedRequest, res: Response) => {
    const txn = await prisma.transaction.findFirst({
      where: { jobId: param(req, "jobId"), status: TransactionStatus.HELD },
    });
    if (!txn) {
      res.status(404).json({ error: "Not found" });
      return;
    }
    await prisma.transaction.update({
      where: { id: txn.id },
      data: { status: TransactionStatus.REFUNDED },
    });
    res.json({ ok: true });
  }
);

router.get("/history", authMiddleware(), async (req: AuthedRequest, res: Response) => {
  const txns = await prisma.transaction.findMany({
    where: {
      OR: [{ customerId: req.user!.dbId }, { workerId: req.user!.dbId }],
    },
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  res.json({ transactions: txns });
});

export default router;
