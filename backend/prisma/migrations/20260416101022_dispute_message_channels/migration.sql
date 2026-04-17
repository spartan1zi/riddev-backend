-- CreateEnum
CREATE TYPE "DisputeMessageChannel" AS ENUM ('ALL', 'ADMIN_CUSTOMER', 'ADMIN_WORKER');

-- AlterTable
ALTER TABLE "DisputeMessage" ADD COLUMN     "channel" "DisputeMessageChannel" NOT NULL DEFAULT 'ALL';

-- CreateIndex
CREATE INDEX "DisputeMessage_disputeId_channel_idx" ON "DisputeMessage"("disputeId", "channel");
