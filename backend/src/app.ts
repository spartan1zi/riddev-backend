import path from "node:path";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import { globalLimiter } from "./middleware/rateLimit";
import { paystackWebhookHandler } from "./routes/payments";
import authRoutes from "./routes/auth";
import usersRoutes from "./routes/users";
import workersRoutes from "./routes/workers";
import jobsRoutes from "./routes/jobs";
import quotesRoutes from "./routes/quotes";
import paymentsRoutes from "./routes/payments";
import chatRoutes from "./routes/chat";
import reviewsRoutes from "./routes/reviews";
import disputesRoutes from "./routes/disputes";
import notificationsRoutes from "./routes/notifications";
import adminRoutes from "./routes/admin";
import reportsRoutes from "./routes/reports";
import walletRoutes from "./routes/wallet";
import uploadsRoutes from "./routes/uploads";

export function createApp(): express.Application {
  const app = express();
  app.use(helmet());
  app.use(cors({ origin: true, credentials: true }));
  app.use(globalLimiter);

  app.use(
    "/uploads/disputes",
    express.static(path.join(process.cwd(), "uploads", "disputes"), {
      maxAge: "7d",
      immutable: false,
    })
  );

  app.post(
    "/api/payments/verify",
    express.raw({ type: "application/json" }),
    paystackWebhookHandler
  );

  app.use(express.json({ limit: "2mb" }));

  app.use("/api/uploads", uploadsRoutes);
  app.use("/api/auth", authRoutes);
  app.use("/api/users", usersRoutes);
  app.use("/api/workers", workersRoutes);
  app.use("/api/jobs", jobsRoutes);
  app.use("/api/quotes", quotesRoutes);
  app.use("/api/payments", paymentsRoutes);
  app.use("/api/wallet", walletRoutes);
  app.use("/api/chat", chatRoutes);
  app.use("/api/reviews", reviewsRoutes);
  app.use("/api/disputes", disputesRoutes);
  app.use("/api/notifications", notificationsRoutes);
  app.use("/api/admin", adminRoutes);
  app.use("/api/reports", reportsRoutes);

  app.get("/health", (_req, res) => res.json({ ok: true }));

  return app;
}
