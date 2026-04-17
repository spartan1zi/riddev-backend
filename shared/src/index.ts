/** Shared constants and types for RidDev Services (backend consumes via file: link). */

export const ACCRA_DEFAULT = { lat: 5.6037, lng: -0.187 };
export const TIMEZONE_ACCRA = "Africa/Accra";
export const CURRENCY_CODE = "GHS";

/** Basis points: 1500 = 15% */
export const DEFAULT_COMMISSION_BPS = 1500;
export const GOLD_TIER_COMMISSION_BPS = 1000;
export const TRUST_FEE_BPS = 500; // 5% on top for customer

export const QUOTE_EXPIRY_MS = 2 * 60 * 60 * 1000;
export const MAX_QUOTES_PER_JOB = 5;
export const MAX_QUOTE_DISTANCE_KM = 20;
export const ABANDONED_PAYMENT_GRACE_MS = 45 * 60 * 1000;

export enum UserRole {
  CUSTOMER = "CUSTOMER",
  WORKER = "WORKER",
  ADMIN = "ADMIN",
}
