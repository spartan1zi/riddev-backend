import admin from "firebase-admin";

let initialized = false;

export function initFirebase(): void {
  if (initialized) return;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, "\n");
  if (!projectId || !clientEmail || !privateKey) {
    console.warn("[firebase] Skipping init — missing FIREBASE_* env vars");
    return;
  }
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId,
      clientEmail,
      privateKey,
    }),
  });
  initialized = true;
}

export async function sendPushNotification(
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  if (!initialized) return;
  const flat = data
    ? Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, v == null ? "" : String(v)])
      )
    : {};
  await admin.messaging().send({
    token: fcmToken,
    notification: { title, body },
    data: flat,
    android: { priority: "high" as const },
    apns: { payload: { aps: { sound: "default" } } },
  });
}
