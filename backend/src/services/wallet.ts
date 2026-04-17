import type { Prisma } from "@prisma/client";
import {
  WalletLedgerDirection,
  WalletLedgerStatus,
  WalletLedgerType,
} from "@prisma/client";
import { prisma } from "../lib/prisma";

async function getWalletRow(
  db: Prisma.TransactionClient,
  userId: string
) {
  let w = await db.wallet.findUnique({ where: { userId } });
  if (!w) {
    w = await db.wallet.create({
      data: { userId, balancePesewas: 0 },
    });
  }
  return w;
}

export async function getOrCreateWallet(userId: string) {
  return getWalletRow(prisma, userId);
}

export async function creditWalletLedger(
  tx: Prisma.TransactionClient,
  userId: string,
  amountPesewas: number,
  type: WalletLedgerType,
  description: string,
  options?: {
    jobId?: string | null;
    reference?: string | null;
    /** Admin settlement / refunds — credit even when the wallet is locked. */
    bypassWalletLock?: boolean;
  }
) {
  if (amountPesewas <= 0) {
    throw new Error("Amount must be positive");
  }
  const wallet = await getWalletRow(tx, userId);
  if (wallet.isLocked && !options?.bypassWalletLock) {
    throw new Error("Wallet is locked");
  }
  const before = wallet.balancePesewas;
  const after = before + amountPesewas;
  await tx.wallet.update({
    where: { id: wallet.id },
    data: { balancePesewas: after },
  });
  await tx.walletLedgerEntry.create({
    data: {
      walletId: wallet.id,
      type,
      direction: WalletLedgerDirection.CREDIT,
      amountPesewas,
      balanceBefore: before,
      balanceAfter: after,
      description,
      reference: options?.reference ?? undefined,
      jobId: options?.jobId ?? undefined,
      status: WalletLedgerStatus.COMPLETED,
    },
  });
  return after;
}

export async function debitWalletLedger(
  tx: Prisma.TransactionClient,
  userId: string,
  amountPesewas: number,
  type: WalletLedgerType,
  description: string,
  options?: { jobId?: string | null; reference?: string | null }
) {
  if (amountPesewas <= 0) {
    throw new Error("Amount must be positive");
  }
  const wallet = await getWalletRow(tx, userId);
  if (wallet.isLocked) {
    throw new Error("Wallet is locked");
  }
  if (wallet.balancePesewas < amountPesewas) {
    throw new Error("Insufficient wallet balance");
  }
  const before = wallet.balancePesewas;
  const after = before - amountPesewas;
  await tx.wallet.update({
    where: { id: wallet.id },
    data: { balancePesewas: after },
  });
  await tx.walletLedgerEntry.create({
    data: {
      walletId: wallet.id,
      type,
      direction: WalletLedgerDirection.DEBIT,
      amountPesewas,
      balanceBefore: before,
      balanceAfter: after,
      description,
      reference: options?.reference ?? undefined,
      jobId: options?.jobId ?? undefined,
      status: WalletLedgerStatus.COMPLETED,
    },
  });
  return after;
}

export async function sumCustomerEscrowHeldPesewas(customerId: string) {
  const agg = await prisma.transaction.aggregate({
    where: {
      customerId,
      status: "HELD",
    },
    _sum: { amountPesewas: true },
  });
  return agg._sum.amountPesewas ?? 0;
}
