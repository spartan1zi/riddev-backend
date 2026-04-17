import crypto from "crypto";

export function verifyPaystackSignature(rawBody: string, signature: string | undefined): boolean {
  const secret = process.env.PAYSTACK_SECRET_KEY;
  if (!secret || !signature) return false;
  const hash = crypto.createHmac("sha512", secret).update(rawBody).digest("hex");
  return hash === signature;
}
