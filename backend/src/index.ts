import "dotenv/config";
import { createServer } from "http";
import { Server } from "socket.io";
import { createApp } from "./app.js";
import { startCronJobs } from "./cron";
import { initFirebase } from "./lib/firebase";
import { setRealtimeServer } from "./lib/realtime";
import { verifyAccess } from "./utils/jwt";

initFirebase();
startCronJobs();

const app = createApp();
const httpServer = createServer(app);

const io = new Server(httpServer, {
  cors: { origin: true },
});

setRealtimeServer(io);

io.use((socket, next) => {
  const token =
    socket.handshake.auth?.token ??
    (socket.handshake.headers.authorization as string)?.replace("Bearer ", "");
  if (!token) {
    next(new Error("Unauthorized"));
    return;
  }
  try {
    const payload = verifyAccess(token);
    socket.data.userId = payload.sub;
    socket.data.role = payload.role;
    next();
  } catch {
    next(new Error("Unauthorized"));
  }
});

io.on("connection", (socket) => {
  const userId = socket.data.userId as string;
  const role = socket.data.role as string;
  void socket.join(`user:${userId}`);
  if (role === "WORKER") {
    void socket.join("workers:feed");
  }
  if (role === "ADMIN") {
    void socket.join("admins:all");
  }

  socket.on("join:dispute", (disputeId: string) => {
    if (typeof disputeId === "string" && disputeId.length > 0) {
      void socket.join(`dispute:${disputeId}`);
    }
  });
  socket.on("leave:dispute", (disputeId: string) => {
    if (typeof disputeId === "string" && disputeId.length > 0) {
      void socket.leave(`dispute:${disputeId}`);
    }
  });

  socket.on("join:job", (jobId: string) => {
    if (typeof jobId === "string" && jobId.length > 0) {
      void socket.join(`job:${jobId}`);
    }
  });
  socket.on("leave:job", (jobId: string) => {
    if (typeof jobId === "string" && jobId.length > 0) {
      void socket.leave(`job:${jobId}`);
    }
  });
  socket.on("worker:location", (payload: { jobId: string; lat: number; lng: number }) => {
    socket.to(`job:${payload.jobId}`).emit("worker:location", payload);
  });
});

const port = Number(process.env.PORT) || 4000;
httpServer.listen(port, () => {
  console.log(`RidDev API listening on :${port}`);
});
