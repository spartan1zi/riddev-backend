import { z } from "zod";

export const registerSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  phone: z.string().min(10),
  password: z.string().min(8),
  role: z.enum(["CUSTOMER", "WORKER"]),
});

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

export const refreshSchema = z.object({
  refreshToken: z.string(),
});

export const verifyPhoneSchema = z.object({
  phone: z.string().min(10),
  code: z.string().length(6),
});

export const requestOtpSchema = z.object({
  phone: z.string().min(10),
});
