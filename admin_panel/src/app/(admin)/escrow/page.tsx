"use client";

import { GlassPanel } from "@/components/GlassPanel";
import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";
import { getAdminToken } from "@/lib/auth";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type Holding = {
  id: string;
  amountPesewas: number;
  platformFeePesewas: number;
  workerAmountPesewas: number;
  status: string;
  createdAt: string;
  job: {
    id: string;
    title: string;
    status: string;
    customerId: string;
    workerId: string | null;
  };
  customer: { id: string; name: string; email: string };
  worker: { id: string; name: string; email: string };
};

function ghs(p: number) {
  return `GHS ${(p / 100).toFixed(2)}`;
}

export default function EscrowPage() {
  const [holdings, setHoldings] = useState<Holding[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    if (!getAdminToken()) {
      setError("Not logged in.");
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await adminApiFetch("/api/admin/escrow/holdings");
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, `Failed to load (${res.status})`));
        setHoldings([]);
        return;
      }
      setHoldings(Array.isArray(data.holdings) ? data.holdings : []);
    } catch {
      setError("Cannot reach API.");
      setHoldings([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const totalHeld = holdings.reduce((s, h) => s + h.amountPesewas, 0);

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Escrow holdings</h1>
      <p className="mb-6 max-w-3xl text-sm text-gray-600">
        Funds held after customer payment, before release to the worker. Resolve disputes from{" "}
        <Link href="/disputes" className="admin-link">
          Disputes
        </Link>{" "}
        — refund credits the customer wallet; pay worker releases the worker share (same as normal completion).
      </p>

      {error && (
        <GlassPanel className="mb-4 !border-red-200 !from-red-500/5">
          <p className="text-sm text-red-800">{error}</p>
        </GlassPanel>
      )}

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <GlassPanel dense>
          <div className="text-xs font-semibold uppercase tracking-wide text-gray-500">Held transactions</div>
          <div className="mt-1 text-2xl font-bold text-gray-900">{loading ? "…" : holdings.length}</div>
        </GlassPanel>
        <GlassPanel dense>
          <div className="text-xs font-semibold uppercase tracking-wide text-gray-500">Total customer funds in escrow</div>
          <div className="mt-1 text-2xl font-bold text-amber-800">{loading ? "…" : ghs(totalHeld)}</div>
        </GlassPanel>
      </div>

      <div className="mb-4 flex justify-end">
        <button type="button" onClick={() => void load()} className="admin-btn-secondary">
          Refresh
        </button>
      </div>

      {loading ? (
        <p className="text-gray-500">Loading…</p>
      ) : (
        <div className="admin-table-shell">
          <table className="w-full min-w-[960px] text-left text-sm">
            <thead className="border-b border-gray-200/80 bg-gray-50/90">
              <tr>
                <th className="px-3 py-3 font-semibold text-gray-700">Job</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Customer</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Worker</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Total paid (held)</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Worker share</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Job status</th>
              </tr>
            </thead>
            <tbody>
              {holdings.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-10 text-center text-gray-500">
                    No escrow held — no pending payments in HELD state.
                  </td>
                </tr>
              ) : (
                holdings.map((h) => (
                  <tr key={h.id} className="border-b border-gray-100/90 hover:bg-amber-500/[0.04]">
                    <td className="px-3 py-2.5">
                      <div className="font-medium text-gray-900">{h.job.title}</div>
                      <div className="font-mono text-xs text-gray-400">{h.job.id}</div>
                    </td>
                    <td className="px-3 py-2.5 text-gray-700">
                      {h.customer.name}
                      <div className="text-xs text-gray-500">{h.customer.email}</div>
                    </td>
                    <td className="px-3 py-2.5 text-gray-700">
                      {h.worker.name}
                      <div className="text-xs text-gray-500">{h.worker.email}</div>
                    </td>
                    <td className="px-3 py-2.5 font-medium text-amber-900">{ghs(h.amountPesewas)}</td>
                    <td className="px-3 py-2.5 text-gray-800">{ghs(h.workerAmountPesewas)}</td>
                    <td className="px-3 py-2.5 text-gray-600">{h.job.status}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
