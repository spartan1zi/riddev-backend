"use client";

import { GlassPanel } from "@/components/GlassPanel";
import { adminApiFetch } from "@/lib/adminApi";
import { getAdminToken } from "@/lib/auth";
import { messageFromApiBody } from "@/lib/apiError";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";

type Row = {
  id: string;
  name: string;
  email: string;
  role: string;
};

export default function DashboardPage() {
  const [users, setUsers] = useState<Row[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const token = getAdminToken();
    if (!token) {
      setError("Not logged in.");
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await adminApiFetch("/api/admin/users");
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(
          messageFromApiBody(
            data,
            `Request failed (${res.status}). Check that the backend is running and NEXT_PUBLIC_API_URL matches it.`
          )
        );
        setUsers([]);
        return;
      }
      const list = Array.isArray(data.users) ? data.users : [];
      setUsers(
        list.map((u: { id: string; name: string; email: string; role: string }) => ({
          id: u.id,
          name: u.name,
          email: u.email,
          role: u.role,
        }))
      );
    } catch {
      setError(
        "Cannot reach API. Create admin_panel/.env.local with NEXT_PUBLIC_API_URL=http://localhost:4000 (or your backend URL), restart next dev, and ensure the API is running."
      );
      setUsers([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const counts = useMemo(() => {
    const byRole = { CUSTOMER: 0, WORKER: 0, ADMIN: 0 };
    for (const u of users) {
      if (u.role === "CUSTOMER") byRole.CUSTOMER += 1;
      else if (u.role === "WORKER") byRole.WORKER += 1;
      else if (u.role === "ADMIN") byRole.ADMIN += 1;
    }
    return { total: users.length, ...byRole };
  }, [users]);

  const preview = users.slice(0, 12);

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Dashboard</h1>
      <p className="mb-6 text-sm text-gray-600">
        User data loads from <code className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs">GET /api/admin/users</code>
        . The full searchable list is on{" "}
        <Link href="/users" className="admin-link">
          Users
        </Link>
        .
      </p>

      {error && (
        <GlassPanel className="mb-6 !border-red-200/80 !from-red-500/5 p-4">
          <p className="text-sm text-red-800">{error}</p>
        </GlassPanel>
      )}

      <div className="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {[
          { label: "Total users", value: loading ? "…" : String(counts.total) },
          { label: "Customers", value: loading ? "…" : String(counts.CUSTOMER) },
          { label: "Workers", value: loading ? "…" : String(counts.WORKER) },
          { label: "Admins", value: loading ? "…" : String(counts.ADMIN) },
        ].map((c) => (
          <GlassPanel key={c.label} dense>
            <div className="text-xs font-semibold uppercase tracking-wide text-gray-500">{c.label}</div>
            <div className="mt-1 text-3xl font-bold tabular-nums text-gray-900">{c.value}</div>
          </GlassPanel>
        ))}
      </div>

      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold text-gray-900">Recent users</h2>
        <div className="flex gap-2">
          <button type="button" onClick={() => void load()} className="admin-btn-secondary">
            Refresh
          </button>
          <Link href="/users" className="admin-btn-primary inline-block px-4 py-2 text-center">
            Open full Users list
          </Link>
        </div>
      </div>

      {loading ? (
        <p className="text-gray-500">Loading users…</p>
      ) : error ? null : (
        <div className="admin-table-shell">
          <table className="w-full min-w-[560px] text-left text-sm">
            <thead className="border-b border-gray-200/80 bg-gray-50/90">
              <tr>
                <th className="px-3 py-3 font-semibold text-gray-700">Role</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Name</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Email</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Action</th>
              </tr>
            </thead>
            <tbody>
              {preview.length === 0 ? (
                <tr>
                  <td colSpan={4} className="px-4 py-10 text-center text-gray-500">
                    No users in the database yet.
                  </td>
                </tr>
              ) : (
                preview.map((u) => (
                  <tr key={u.id} className="border-b border-gray-100/90 hover:bg-amber-500/[0.04]">
                    <td className="px-3 py-2.5 text-gray-700">{u.role}</td>
                    <td className="px-3 py-2.5 font-medium text-gray-900">{u.name}</td>
                    <td className="px-3 py-2.5 text-gray-600">{u.email}</td>
                    <td className="px-3 py-2.5">
                      <Link
                        href={`/wallets?userId=${encodeURIComponent(u.id)}&name=${encodeURIComponent(u.name)}`}
                        className="admin-link text-sm"
                      >
                        Credit wallet
                      </Link>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {!loading && !error && users.length > 12 && (
        <p className="mt-3 text-xs text-gray-500">Showing 12 of {users.length}. See all on the Users page.</p>
      )}
    </div>
  );
}
