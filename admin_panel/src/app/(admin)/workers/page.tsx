"use client";

import { adminApiFetch } from "@/lib/adminApi";
import { getAdminToken } from "@/lib/auth";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type WorkerRow = {
  id: string;
  name: string;
  email: string;
  phone: string;
  workerProfile: {
    backgroundCheckStatus: string;
  } | null;
  wallet: { balancePesewas: number; isLocked?: boolean } | null;
};

export default function WorkersPage() {
  const [workers, setWorkers] = useState<WorkerRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const token = getAdminToken();
    if (!token) return;
    setLoading(true);
    setError(null);
    try {
      const res = await adminApiFetch("/api/admin/workers");
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(typeof data.error === "string" ? data.error : "Failed to load workers");
        return;
      }
      setWorkers(data.workers ?? []);
    } catch {
      setError("Cannot reach API. Set NEXT_PUBLIC_API_URL to your backend (e.g. http://localhost:4000).");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function verifyWorker(userId: string) {
    const token = getAdminToken();
    if (!token) return;
    const res = await adminApiFetch(`/api/admin/workers/${userId}/verify`, {
      method: "PUT",
    });
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      setError(typeof data.error === "string" ? data.error : "Verify failed");
      return;
    }
    await load();
  }

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Workers</h1>
      <p className="mb-6 text-sm text-gray-600">
        Approve workers for the marketplace. Uses{" "}
        <code className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs">PUT /api/admin/workers/:id/verify</code>.
      </p>
      {error && (
        <p className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-2 text-sm text-red-800">{error}</p>
      )}
      {loading ? (
        <p className="text-gray-500">Loading…</p>
      ) : (
        <div className="admin-table-shell">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead className="border-b border-gray-200/80 bg-gray-50/90">
              <tr>
                <th className="px-4 py-3 font-semibold text-gray-700">Name</th>
                <th className="px-4 py-3 font-semibold text-gray-700">Email</th>
                <th className="px-4 py-3 font-semibold text-gray-700">Phone</th>
                <th className="px-4 py-3 font-semibold text-gray-700">Wallet</th>
                <th className="px-4 py-3 font-semibold text-gray-700">Verify</th>
                <th className="px-4 py-3 font-semibold text-gray-700">Action</th>
              </tr>
            </thead>
            <tbody>
              {workers.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-gray-500">
                    No workers yet. Register from the worker app (same API).
                  </td>
                </tr>
              ) : (
                workers.map((w) => {
                  const status = w.workerProfile?.backgroundCheckStatus ?? "—";
                  const approved = status === "APPROVED";
                  const bal = w.wallet?.balancePesewas;
                  const locked = w.wallet?.isLocked;
                  return (
                    <tr key={w.id} className="border-b border-gray-100/90 hover:bg-amber-500/[0.04]">
                      <td className="px-4 py-3 font-medium text-gray-900">{w.name}</td>
                      <td className="px-4 py-3 text-gray-600">{w.email}</td>
                      <td className="px-4 py-3 text-gray-600">{w.phone}</td>
                      <td className="px-4 py-3 text-gray-800">
                        {locked ? (
                          <span className="font-medium text-amber-600">Locked</span>
                        ) : bal == null ? (
                          "—"
                        ) : (
                          `GHS ${(bal / 100).toFixed(2)}`
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={
                            approved
                              ? "rounded-lg bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800"
                              : "rounded-lg bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-900"
                          }
                        >
                          {status}
                        </span>
                      </td>
                      <td className="space-x-2 px-4 py-3">
                        <Link
                          href={`/wallets?userId=${encodeURIComponent(w.id)}&name=${encodeURIComponent(w.name)}`}
                          className="admin-link text-sm"
                        >
                          Credit
                        </Link>
                        {!approved ? (
                          <button
                            type="button"
                            onClick={() => void verifyWorker(w.id)}
                            className="rounded-xl bg-gradient-to-r from-amber-500 to-amber-600 px-3 py-1.5 text-xs font-semibold text-white shadow-md hover:from-amber-600 hover:to-amber-700"
                          >
                            Approve
                          </button>
                        ) : (
                          <span className="text-xs text-gray-500">OK</span>
                        )}
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
