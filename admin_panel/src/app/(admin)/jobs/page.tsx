"use client";

import { GlassPanel } from "@/components/GlassPanel";
import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";
import { getAdminToken } from "@/lib/auth";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type JobRow = {
  id: string;
  title: string;
  status: string;
  category: string;
  agreedPricePesewas: number | null;
  createdAt: string;
  scheduledAt: string | null;
  completedAt: string | null;
  customer: { id: string; name: string; email: string };
  worker: { id: string; name: string; email: string } | null;
};

function ghs(p: number | null) {
  if (p == null) return "—";
  return `GHS ${(p / 100).toFixed(2)}`;
}

export default function AdminJobsPage() {
  const [jobs, setJobs] = useState<JobRow[]>([]);
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
      const res = await adminApiFetch("/api/admin/jobs");
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, `Failed (${res.status})`));
        setJobs([]);
        return;
      }
      setJobs(Array.isArray(data.jobs) ? data.jobs : []);
    } catch {
      setError("Cannot reach API.");
      setJobs([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Jobs</h1>
      <p className="mb-6 max-w-3xl text-sm text-gray-600">
        All jobs in the system, newest first. Escrow held against a job appears under{" "}
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
          <table className="w-full min-w-[960px] text-left text-sm">
            <thead className="border-b border-gray-200/80 bg-gray-50/90">
              <tr>
                <th className="px-3 py-3 font-semibold text-gray-700">Title</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Status</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Category</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Agreed price</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Customer</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Worker</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Created</th>
              </tr>
            </thead>
            <tbody>
              {jobs.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-10 text-center text-gray-500">
                    No jobs yet.
                  </td>
                </tr>
              ) : (
                jobs.map((j) => (
                  <tr key={j.id} className="border-b border-gray-100/80 hover:bg-amber-500/5">
                    <td className="max-w-[220px] px-3 py-2.5 font-medium text-gray-900">
                      <span className="line-clamp-2" title={j.title}>
                        {j.title}
                      </span>
                      <div className="font-mono text-[10px] text-gray-400">{j.id.slice(0, 8)}…</div>
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5">
                      <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-semibold text-gray-800">
                        {j.status}
                      </span>
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-700">{j.category}</td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-800">{ghs(j.agreedPricePesewas)}</td>
                    <td className="px-3 py-2.5 text-gray-700">
                      <div>{j.customer.name}</div>
                      <div className="text-xs text-gray-500">{j.customer.email}</div>
                    </td>
                    <td className="px-3 py-2.5 text-gray-700">
                      {j.worker ? (
                        <>
                          <div>{j.worker.name}</div>
                          <div className="text-xs text-gray-500">{j.worker.email}</div>
                        </>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-600">
                      {new Date(j.createdAt).toLocaleString()}
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
