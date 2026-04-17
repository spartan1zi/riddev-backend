"use client";

import { GlassPanel } from "@/components/GlassPanel";
import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";
import { getAdminToken } from "@/lib/auth";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type TxRow = {
  id: string;
  status: string;
  amountPesewas: number;
  platformFeePesewas: number;
  workerAmountPesewas: number;
  paystackReference: string | null;
  createdAt: string;
  releasedAt: string | null;
  job: { id: string; title: string; status: string };
  customer: { id: string; name: string; email: string };
  worker: { id: string; name: string; email: string };
};

function ghs(p: number) {
  return `GHS ${(p / 100).toFixed(2)}`;
}

export default function AdminPaymentsPage() {
  const [transactions, setTransactions] = useState<TxRow[]>([]);
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
      const res = await adminApiFetch("/api/admin/payments");
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, `Failed (${res.status})`));
        setTransactions([]);
        return;
      }
      setTransactions(Array.isArray(data.transactions) ? data.transactions : []);
    } catch {
      setError("Cannot reach API.");
      setTransactions([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Payments</h1>
      <p className="mb-6 max-w-3xl text-sm text-gray-600">
        Payment / escrow records (Paystack-backed job payments). Currently <strong>HELD</strong> rows are also listed on{" "}
        <Link href="/escrow" className="admin-link">
          Escrow
        </Link>
        .
      </p>

      {error && (
        <GlassPanel className="mb-4 !border-red-200 !from-red-500/5">
          <p className="text-sm text-red-800">{error}</p>
        </GlassPanel>
      )}

      <div className="mb-4 flex justify-end">
        <button type="button" onClick={() => void load()} className="admin-btn-secondary">
          Refresh
        </button>
      </div>

      {loading ? (
        <p className="text-gray-500">Loading…</p>
      ) : (
        <div className="admin-table-shell">
          <table className="w-full min-w-[1100px] text-left text-sm">
            <thead className="border-b border-gray-200/80 bg-gray-50/90">
              <tr>
                <th className="px-3 py-3 font-semibold text-gray-700">When</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Status</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Total (customer paid)</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Platform fee</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Worker share</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Job</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Customer</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Worker</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Ref</th>
              </tr>
            </thead>
            <tbody>
              {transactions.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-4 py-10 text-center text-gray-500">
                    No payment records yet.
                  </td>
                </tr>
              ) : (
                transactions.map((t) => (
                  <tr key={t.id} className="border-b border-gray-100/80 hover:bg-amber-500/5">
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-600">
                      {new Date(t.createdAt).toLocaleString()}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5">
                      <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-semibold text-gray-800">
                        {t.status}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 font-medium text-gray-900">{ghs(t.amountPesewas)}</td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-700">{ghs(t.platformFeePesewas)}</td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-700">{ghs(t.workerAmountPesewas)}</td>
                    <td className="max-w-[200px] px-3 py-2.5">
                      <div className="line-clamp-2 font-medium text-gray-900" title={t.job.title}>
                        {t.job.title}
                      </div>
                      <div className="text-xs text-gray-500">{t.job.status}</div>
                    </td>
                    <td className="px-3 py-2.5 text-gray-700">
                      <div>{t.customer.name}</div>
                      <div className="text-xs text-gray-500">{t.customer.email}</div>
                    </td>
                    <td className="px-3 py-2.5 text-gray-700">
                      <div>{t.worker.name}</div>
                      <div className="text-xs text-gray-500">{t.worker.email}</div>
                    </td>
                    <td className="max-w-[140px] break-all px-3 py-2.5 font-mono text-xs text-gray-600">
                      {t.paystackReference ?? "—"}
                    </td>
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
