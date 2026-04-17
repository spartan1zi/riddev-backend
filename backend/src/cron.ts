import cron from "node-cron";
import { prisma } from "./lib/prisma";
import { QuoteStatus, JobStatus, TransactionStatus, WorkerTier } from "@prisma/client";
import { notifyUserNotificationsChanged } from "./lib/realtime";
import { sendPushToUser } from "./services/pushNotifications";

export function startCronJobs(): void {
  cron.schedule("*/30 * * * *", async () => {
    const now = new Date();
    await prisma.quote.updateMany({
      where: {
        status: { in: [QuoteStatus.PENDING, QuoteStatus.COUNTERED] },
        expiresAt: { lt: now },
      },
      data: { status: QuoteStatus.EXPIRED },
    });

    const grace = new Date(Date.now() - 45 * 60 * 1000);
    const stuck = await prisma.job.findMany({
      where: {
        status: JobStatus.ACCEPTED,
        quoteAcceptedAt: { lt: grace },
      },
    });
    for (const job of stuck) {
      const paid = await prisma.transaction.findFirst({
        where: {
          jobId: job.id,
          status: { in: [TransactionStatus.PENDING, TransactionStatus.HELD] },
        },
      });
      if (!paid) {
        await prisma.notification.create({
          data: {
            userId: job.customerId,
            title: "Complete payment",
            body: "Your accepted quote still needs payment.",
            type: "payment_abandoned",
            data: { jobId: job.id },
          },
        });
        notifyUserNotificationsChanged(job.customerId, { reason: "payment_abandoned" });
        void sendPushToUser(job.customerId, "Complete payment", "Your accepted quote still needs payment.", {
          jobId: job.id,
          type: "payment_abandoned",
        });
      }
    }
  });

  cron.schedule("5 * * * *", async () => {
    const workers = await prisma.workerProfile.findMany();
    for (const w of workers) {
      let tier: WorkerTier = WorkerTier.BRONZE;
      if (w.totalJobsCompleted >= 100 && w.rating >= 4.5) tier = WorkerTier.GOLD;
      else if (w.totalJobsCompleted >= 50 && w.rating >= 4.0) tier = WorkerTier.SILVER;
      const commission =
        tier === WorkerTier.GOLD ? 1000 : tier === WorkerTier.SILVER ? 1200 : 1500;
      if (w.tier !== tier || w.commissionRateBps !== commission) {
        await prisma.workerProfile.update({
          where: { id: w.id },
          data: { tier, commissionRateBps: commission },
        });
      }
    }
  });
}
