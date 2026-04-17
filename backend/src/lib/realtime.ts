import type { Server } from "socket.io";
import { prisma } from "./prisma";

let io: Server | null = null;

export function setRealtimeServer(server: Server) {
  io = server;
}

export function getRealtimeServer(): Server | null {
  return io;
}

export function emitToJobRoom(jobId: string, event: string, payload: unknown) {
  io?.to(`job:${jobId}`).emit(event, payload);
}

/**
 * Notifies everyone watching this job (Socket.IO room) plus affected users’ personal rooms.
 * Use `skipWorkersFeed` for high-frequency events (e.g. chat) so all workers don’t refetch.
 */
export async function notifyJobChange(
  jobId: string,
  reason: string,
  options?: { skipWorkersFeed?: boolean }
) {
  const s = io;
  if (!s) return;

  s.to(`job:${jobId}`).emit("job:event", { jobId, reason });

  const job = await prisma.job.findUnique({ where: { id: jobId } });
  if (!job) return;

  s.to(`user:${job.customerId}`).emit("me:jobs", { jobId, reason });

  const quoteRows = await prisma.quote.findMany({
    where: { jobId },
    select: { workerId: true },
  });
  const notifyWorkerIds = new Set<string>();
  if (job.workerId) notifyWorkerIds.add(job.workerId);
  for (const q of quoteRows) notifyWorkerIds.add(q.workerId);

  for (const wid of notifyWorkerIds) {
    s.to(`user:${wid}`).emit("me:jobs", { jobId, reason });
  }

  if (!options?.skipWorkersFeed) {
    s.to("workers:feed").emit("jobs:feed", { jobId, reason });
  }
}

/** New OPEN job — customer + all workers watching the feed. */
export function notifyNewJob(jobId: string, customerId: string) {
  const s = io;
  if (!s) return;
  s.to(`user:${customerId}`).emit("me:jobs", { jobId, reason: "new_job" });
  s.to("workers:feed").emit("jobs:feed", { jobId, reason: "new_job" });
}

/** New dispute thread message — room `dispute:{id}`, both parties, and all admins. */
export function notifyDisputeMessageEvent(disputeId: string, payload: unknown) {
  const s = io;
  if (!s) return;
  s.to(`dispute:${disputeId}`).emit("dispute:message", payload);
  s.to("admins:all").emit("dispute:message", payload);
}

/** Admin changed Everyone / lock settings — clients should refresh thread + rules. */
export function notifyDisputeChatSettingsEvent(
  disputeId: string,
  payload: { everyoneChannelEnabled: boolean; disputeChatLocked: boolean }
) {
  const s = io;
  if (!s) return;
  s.to(`dispute:${disputeId}`).emit("dispute:chat_settings", payload);
  s.to("admins:all").emit("dispute:chat_settings", { disputeId, ...payload });
}

/** New or updated in-app notification row — badge refresh on mobile/web (room `user:{id}`). */
export function notifyUserNotificationsChanged(userId: string, payload: Record<string, unknown> = {}) {
  const s = io;
  if (!s) return;
  s.to(`user:${userId}`).emit("notifications:update", payload);
}
