import rateLimit from "express-rate-limit";

const windowMs = 15 * 60 * 1000;

/**
 * Max HTTP requests per IP per window. Default was 100 — on localhost every app
 * (customer + worker + admin + refreshes) shares one IP, so normal use hit 429 Too Many Requests.
 * Override with `RATE_LIMIT_MAX` in `.env` (set `0` to disable the global limiter in dev only).
 */
const parsed =
  process.env.RATE_LIMIT_MAX !== undefined && process.env.RATE_LIMIT_MAX !== ""
    ? Number(process.env.RATE_LIMIT_MAX)
    : NaN;
let max = Number.isFinite(parsed) ? parsed : 2500;
if (max < 0) max = 2500;

export const globalLimiter = rateLimit({
  windowMs,
  max,
  standardHeaders: true,
  legacyHeaders: false,
  /** `RATE_LIMIT_MAX=0` turns off the global limiter (useful for local debugging). */
  skip: () => max === 0,
});
