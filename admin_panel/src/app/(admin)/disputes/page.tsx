"use client";

import { GlassPanel } from "@/components/GlassPanel";
import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";
import { getAdminToken } from "@/lib/auth";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type DisputeListRow = {
  id: string;
  status: string;
  reason: string;
  createdAt: string;
  resolvedAt: string | null;
  evidencePhotos: string[];
  job: {
    id: string;
    title: string;
    status: string;
    customer: { id: string; name: string; email: string };
    worker: { id: string; name: string; email: string } | null;
  };
  raisedBy: { id: string; name: string; role: string };
};

export default function AdminDisputesListPage() {
  const [disputes, setDisputes] = useState<DisputeListRow[]>([]);
  const [includeResolved, setIncludeResolved] = useState(false);
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
      const q = includeResolved ? "?includeResolved=true" : "";
      const res = await adminApiFetch(`/api/admin/disputes${q}`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, `Failed (${res.status})`));
        setDisputes([]);
        return;
      }
      setDisputes(Array.isArray(data.disputes) ? data.disputes : []);
    } catch {
      setError("Cannot reach API.");
      setDisputes([]);
    } finally {
      setLoading(false);
    }
  }, [includeResolved]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Disputes</h1>
      <p className="mb-4 max-w-3xl text-sm text-gray-600">
        Select a row to open the full dispute, read the customer and worker story, view photo evidence, and apply a
        settlement. Escrow context is on{" "}
        <Link href="/escrow" className="admin-link">
          Escrow
        </Link>
        .
      </p>

      <label className="mb-6 flex cursor-pointer items-center gap-2 text-sm text-gray-700">
        <input
          type="checkbox"
          checked={includeResolved}
          onChange={(e) => setIncludeResolved(e.target.checked)}
        />
        Show resolved disputes
      </label>

      {error && (
        <GlassPanel className="mb-4 !border-red-200 !from-red-500/5">
          <p className="text-sm text-red-800">{error}</p>
        </GlassPanel>
      )}

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <button type="button" onClick={() => void load()} className="admin-btn-secondary">
          Refresh
        </button>
      </div>

      {loading ? (
        <p className="text-gray-500">Loading…</p>
      ) : disputes.length === 0 ? (
        <GlassPanel>
          <p className="text-sm text-gray-600">No disputes to show.</p>
        </GlassPanel>
      ) : (
        <div className="admin-table-shell">
          <table className="w-full min-w-[800px] text-left text-sm">
            <thead className="border-b border-gray-200/80 bg-gray-50/90">
              <tr>
                <th className="px-3 py-3 font-semibold text-gray-700">Status</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Job</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Raised by</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Opened</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Photos</th>
                <th className="px-3 py-3 font-semibold text-gray-700"> </th>
              </tr>
            </thead>
            <tbody>
              {disputes.map((d) => {
                const photoCount = Array.isArray(d.evidencePhotos) ? d.evidencePhotos.length : 0;
                const rawReason = (d.reason ?? "").replace(/\s+/g, " ").trim();
                const previewSnippet =
                  rawReason.length > 72 ? `${rawReason.slice(0, 72)}…` : rawReason;
                return (
                  <tr key={d.id} className="border-b border-gray-100/80 hover:bg-amber-500/5">
                    <td className="whitespace-nowrap px-3 py-2.5">
                      <span
                        className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${
                          d.status === "RESOLVED"
                            ? "bg-emerald-100 text-emerald-800"
                            : "bg-amber-100 text-amber-900"
                        }`}
                      >
                        {d.status}
                      </span>
                    </td>
                    <td className="max-w-[260px] px-3 py-2.5">
                      <div className="font-medium text-gray-900 line-clamp-2">{d.job.title}</div>
                      <div className="text-xs text-gray-500">{d.job.status}</div>
                      {previewSnippet.length > 0 && (
                        <div className="mt-1 text-xs text-gray-600 line-clamp-2">{previewSnippet}</div>
                      )}
                    </td>
                    <td className="px-3 py-2.5 text-gray-800">
                      <div>{d.raisedBy.name}</div>
                      <div className="text-xs text-gray-500">{d.raisedBy.role}</div>
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-600">
                      {new Date(d.createdAt).toLocaleString()}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-700">
                      {photoCount > 0 ? (
                        <span className="font-semibold text-amber-800">{photoCount}</span>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5">
                      <Link href={`/disputes/${d.id}`} className="admin-link font-semibold">
                        Open →
                      </Link>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
