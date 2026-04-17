-- Dispute chat: admin-controlled Everyone channel + full thread lock

ALTER TABLE "Dispute" ADD COLUMN "everyoneChannelEnabled" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Dispute" ADD COLUMN "disputeChatLocked" BOOLEAN NOT NULL DEFAULT false;
