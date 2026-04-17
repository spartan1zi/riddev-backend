"use client";

import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";
import { getAdminToken } from "@/lib/auth";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";

type WalletInfo = { balancePesewas: number; isLocked: boolean } | null;

type UserRow = {
  id: string;
  name: string;
  email: string;
  phone: string;
  role: string;
  isActive: boolean;
  isSuspended: boolean;
  createdAt: string;
  wallet: WalletInfo;
};

function ghsFromPesewas(p: number | undefined) {
  if (p == null || Number.isNaN(p)) return "—";
  return `GHS ${(p / 100).toFixed(2)}`;
}

export default function UsersPage() {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("");

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
          messageFromApiBody(data, `Failed to load users (${res.status}). Is the backend running and NEXT_PUBLIC_API_URL correct?`)
        );
        return;
      }
      setUsers(Array.isArray(data.users) ? data.users : []);
    } catch {
      setError(
        "Cannot reach API. Set NEXT_PUBLIC_API_URL in .env.local to your backend (e.g. http://localhost:4000) and restart next dev."
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase();
    if (!q) return users;
    return users.filter(
      (u) =>
        u.name.toLowerCase().includes(q) ||
        u.email.toLowerCase().includes(q) ||
        u.phone.includes(q) ||
        u.id.toLowerCase().includes(q) ||
        u.role.toLowerCase().includes(q)
    );
  }, [users, filter]);

  async function copyId(id: string) {
    try {
      await navigator.clipboard.writeText(id);
    } catch {
      /* ignore */
    }
  }

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">All users</h1>
      <p className="mb-4 text-sm text-gray-600">
        Data from <code className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs">GET /api/admin/users</code> (admin
        JWT required). Use <strong className="text-gray-900">Wallet credit</strong> to add test funds.
      </p>
      <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <input
          type="search"
          placeholder="Search name, email, phone, role, or ID…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="admin-input max-w-md"
        />
        <button type="button" onClick={() => void load()} className="admin-btn-secondary shrink-0">
          Refresh
        </button>
      </div>
      {error && (
        <p className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-2 text-sm text-red-800">{error}</p>
      )}
      {loading ? (
        <p className="text-gray-500">Loading…</p>
      ) : (
        <div className="admin-table-shell">
          <table className="w-full min-w-[900px] text-left text-sm">
            <thead className="border-b border-gray-200/80 bg-gray-50/90">
              <tr>
                <th className="px-3 py-3 font-semibold text-gray-700">Role</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Name</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Email</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Phone</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Wallet</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Status</th>
                <th className="px-3 py-3 font-semibold text-gray-700">User ID</th>
                <th className="px-3 py-3 font-semibold text-gray-700">Action</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-4 py-10 text-center text-gray-500">
                    {users.length === 0
                      ? "No users in the database yet."
                      : "No matches for this search."}
                  </td>
                </tr>
              ) : (
                filtered.map((u) => (
                  <tr key={u.id} className="border-b border-gray-100/90 hover:bg-amber-500/[0.04]">
                    <td className="px-3 py-2.5">
                      <span
                        className={
                          u.role === "ADMIN"
                            ? "font-medium text-violet-700"
                            : u.role === "WORKER"
                              ? "font-medium text-amber-700"
                              : "text-gray-700"
                        }
                      >
                        {u.role}
                      </span>
                    </td>
                    <td className="px-3 py-2.5 font-medium text-gray-900">{u.name}</td>
                    <td className="px-3 py-2.5 text-gray-600">{u.email}</td>
                    <td className="px-3 py-2.5 text-gray-600">{u.phone}</td>
                    <td className="px-3 py-2.5 text-gray-800">
                      {u.wallet?.isLocked ? (
                        <span className="font-medium text-amber-600">Locked</span>
                      ) : (
                        ghsFromPesewas(u.wallet?.balancePesewas)
                      )}
                    </td>
                    <td className="px-3 py-2.5">
                      {u.isSuspended ? (
                        <span className="rounded-lg bg-red-100 px-2 py-0.5 text-xs font-medium text-red-800">
                          Suspended
                        </span>
                      ) : u.isActive ? (
                        <span className="rounded-lg bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800">
                          Active
                        </span>
                      ) : (
                        <span className="text-gray-500">Inactive</span>
                      )}
                    </td>
                    <td className="px-3 py-2.5 font-mono text-xs text-gray-500">
                      <button
                        type="button"
                        title="Copy full ID"
                        onClick={() => void copyId(u.id)}
                        className="max-w-[140px] truncate text-left hover:text-amber-700"
                      >
                        {u.id}
                      </button>
                    </td>
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
      <p className="mt-4 text-xs text-gray-500">
        Showing {filtered.length} of {users.length} users (max 500 from API).
      </p>
    </div>
  );
}
