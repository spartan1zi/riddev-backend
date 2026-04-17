import { describe, it, expect, beforeAll } from "vitest";
import request from "supertest";
import { createApp } from "../app";
import { prisma } from "../lib/prisma";

const app = createApp();

let dbAvailable = false;

beforeAll(async () => {
  try {
    await Promise.race([
      prisma.$connect(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("connect timeout")), 3000)
      ),
    ]);
    dbAvailable = true;
  } catch {
    dbAvailable = false;
    console.warn("[e2e] PostgreSQL not reachable — DB-backed tests skipped");
  }
});

describe("RidDev API E2E smoke", () => {
  it("GET /health", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it("registers a customer and creates a job", async () => {
    if (!dbAvailable) {
      return;
    }
    const suffix = `${Date.now()}`;
    const reg = await request(app).post("/api/auth/register").send({
      name: "E2E Customer",
      email: `e2e_${suffix}@test.com`,
      phone: `0244${suffix.slice(-6)}`,
      password: "testpass12",
      role: "CUSTOMER",
    });
    expect(reg.status).toBe(201);
    expect(reg.body.accessToken).toBeDefined();
    const token = reg.body.accessToken as string;

    const job = await request(app)
      .post("/api/jobs")
      .set("Authorization", `Bearer ${token}`)
      .send({
        category: "PLUMBER",
        title: "E2E leak fix",
        description: "Kitchen sink repair test job",
        photos: [],
        locationLat: 5.6037,
        locationLng: -0.187,
        address: "Accra",
      });
    expect(job.status).toBe(201);
    expect(job.body.id).toBeDefined();
    expect(job.body.status).toBe("OPEN");
  });
});
