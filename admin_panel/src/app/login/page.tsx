"use client";

import { setAdminRefreshToken, setAdminToken } from "@/lib/auth";
import { apiBaseUrl } from "@/lib/config";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

export default function AdminLoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const base = apiBaseUrl();
      const res = await fetch(`${base}/api/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim(), password }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(typeof data.error === "string" ? data.error : "Login failed");
        return;
      }
      if (data.user?.role !== "ADMIN") {
        setError("This account is not an admin.");
        return;
      }
      setAdminToken(data.accessToken as string);
      if (typeof data.refreshToken === "string") {
        setAdminRefreshToken(data.refreshToken);
      }
      router.replace("/dashboard");
    } catch {
      const base = apiBaseUrl();
      setError(
        `Cannot reach API at ${base}. Start the backend (cd backend && npm run dev) and ensure NEXT_PUBLIC_API_URL matches the API port (default http://localhost:4000). Restart the admin dev server after changing .env.local.`
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="relative min-h-screen overflow-hidden bg-slate-100 text-slate-900">
      {/* Ambient background — EOD AuthLayout-style */}
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_80%_50%_at_50%_-20%,rgba(217,119,6,0.18),transparent)]" />
      <div className="pointer-events-none absolute -left-32 top-1/4 h-96 w-96 rounded-full bg-amber-400/20 blur-3xl" />
      <div className="pointer-events-none absolute -right-40 bottom-0 h-[28rem] w-[28rem] rounded-full bg-amber-600/15 blur-3xl" />
      <div
        className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(148,163,184,0.06)_1px,transparent_1px),linear-gradient(to_bottom,rgba(148,163,184,0.06)_1px,transparent_1px)] bg-[length:3rem_3rem] [mask-image:radial-gradient(ellipse_60%_50%_at_50%_50%,black_70%,transparent)]"
        aria-hidden
      />

      <div className="relative flex min-h-screen flex-col items-center justify-center px-4 py-12 sm:px-6">
        <div className="mb-8 text-center sm:mb-10">
          <div className="mb-4 flex justify-center">
            <div className="rounded-2xl border border-amber-500/25 bg-gradient-to-br from-amber-500/15 to-amber-600/5 px-6 py-3 shadow-md ring-1 ring-amber-500/20">
              <span className="text-2xl font-black tracking-tight text-amber-800">RidDev</span>
            </div>
          </div>
          <div className="inline-flex items-center gap-2 rounded-full border border-amber-500/25 bg-amber-500/10 px-3 py-1 text-xs font-semibold uppercase tracking-widest text-amber-800">
            Admin access
          </div>
          <h1 className="mt-4 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">Admin sign in</h1>
          <p className="mx-auto mt-2 max-w-md text-sm text-slate-600">
            Manage users, workers, wallets, and disputes. Seed an admin with{" "}
            <code className="rounded bg-slate-200/80 px-1.5 py-0.5 font-mono text-xs text-slate-800">
              npm run db:seed
            </code>{" "}
            in the backend.
          </p>
        </div>

        <div className="relative w-full max-w-[420px] overflow-hidden rounded-2xl border border-slate-200/80 bg-white/85 shadow-[0_25px_50px_-12px_rgba(0,0,0,0.15)] ring-1 ring-slate-900/5 backdrop-blur-xl">
          <div className="h-1 w-full bg-gradient-to-r from-amber-500/0 via-amber-500 to-amber-600/0" />
          <div className="p-8 sm:p-9">
            <form onSubmit={onSubmit} className="space-y-4">
              <div>
                <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-600">
                  Email
                </label>
                <input
                  type="email"
                  autoComplete="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="admin-input"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-600">
                  Password
                </label>
                <input
                  type="password"
                  autoComplete="current-password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="admin-input"
                />
              </div>
              {error && (
                <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">{error}</p>
              )}
              <button type="submit" disabled={busy} className="admin-btn-primary w-full">
                {busy ? "Signing in…" : "Sign in"}
              </button>
            </form>
          </div>
        </div>

        <p className="mt-8 max-w-md text-center text-xs text-slate-500">
          If pages show &quot;Invalid token&quot;, sign out from the admin shell and sign in again so a refresh session
          can be stored.
        </p>
      </div>
    </div>
  );
}
