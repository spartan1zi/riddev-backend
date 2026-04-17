import { prisma } from "../lib/prisma";
import { sendPushNotification } from "../lib/firebase";

/** Send FCM notification if the user has registered a device token. */
export async function sendPushToUser(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  const u = await prisma.user.findUnique({
    where: { id: userId },
    select: { fcmToken: true },
  });
  if (!u?.fcmToken) return;
  try {
    await sendPushNotification(u.fcmToken, title, body, data);
  } catch (e) {
    console.warn("[push] FCM send failed for user", userId, e);
  }
}
