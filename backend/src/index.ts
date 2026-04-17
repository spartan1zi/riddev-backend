import "dotenv/config";
import { createServer } from "http";
import { Server } from "socket.io";
import { createApp } from "./app";
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

// auth middleware
io.use((socket, next) => {
  const token =
    socket.handshake.auth?.token ??
    (socket.handshake.headers.authorization as string)?.replace("Bearer ", "");

  if (!token) return next(new Error("Unauthorized"));

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
  const userId = socket.data.userId;
  const role = socket.data.role;

  socket.join(`user:${userId}`);

  if (role === "WORKER") socket.join("workers:feed");
  if (role === "ADMIN") socket.join("admins:all");

  socket.on("join:job", (jobId) => socket.join(`job:${jobId}`));
  socket.on("leave:job", (jobId) => socket.leave(`job:${jobId}`));

  socket.on("worker:location", (payload) => {
    socket.to(`job:${payload.jobId}`).emit("worker:location", payload);
  });
});

const port = Number(process.env.PORT) || 4000;

httpServer.listen(port, "0.0.0.0", () => {
  console.log(`RidDev API listening on :${port}`);
});
