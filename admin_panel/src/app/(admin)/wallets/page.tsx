"use client";

import { GlassPanel } from "@/components/GlassPanel";
import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";
import { getAdminToken } from "@/lib/auth";
import { useSearchParams } from "next/navigation";
import { FormEvent, Suspense, useEffect, useState } from "react";

function AdminWalletsContent() {
  const searchParams = useSearchParams();
  const [userId, setUserId] = useState("");
  const [prefillLabel, setPrefillLabel] = useState<string | null>(null);
  const [amountGhs, setAmountGhs] = useState("50");
  const [reason, setReason] = useState("Test credit");
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [debitAmountGhs, setDebitAmountGhs] = useState("10");
  const [debitReason, setDebitReason] = useState("Adjustment — disputed funds");
  const [debitMessage, setDebitMessage] = useState<string | null>(null);
  const [debitBusy, setDebitBusy] = useState(false);

  useEffect(() => {
    const id = searchParams.get("userId");
    const name = searchParams.get("name");
    if (id) {
      setUserId(id);
      setPrefillLabel(name ?? null);
    } else {
      setPrefillLabel(null);
    }
  }, [searchParams]);

  async function onCredit(e: FormEvent) {
    e.preventDefault();
    setMessage(null);
    if (!getAdminToken()) {
      setMessage("Not logged in.");
      return;
    }
    const ghs = parseFloat(amountGhs);
    if (Number.isNaN(ghs) || ghs <= 0) {
      setMessage("Invalid amount");
      return;
    }
    const amountPesewas = Math.round(ghs * 100);
    setBusy(true);
    try {
      const res = await adminApiFetch("/api/admin/wallet/credit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          userId: userId.trim(),
          amountPesewas,
          reason: reason.trim(),
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setMessage(messageFromApiBody(data, "Credit failed"));
        return;
      }
      setMessage(`Credited. New balance (pesewas): ${data.balancePesewas ?? "ok"}.`);
    } catch {
      setMessage("Request failed. Is the API running?");
    } finally {
      setBusy(false);
    }
  }

  async function onDebit(e: FormEvent) {
    e.preventDefault();
    setDebitMessage(null);
    if (!getAdminToken()) {
      setDebitMessage("Not logged in.");
      return;
    }
    const ghs = parseFloat(debitAmountGhs);
    if (Number.isNaN(ghs) || ghs <= 0) {
      setDebitMessage("Invalid amount");
      return;
    }
    const amountPesewas = Math.round(ghs * 100);
    setDebitBusy(true);
    try {
      const res = await adminApiFetch("/api/admin/wallet/debit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          userId: userId.trim(),
          amountPesewas,
          reason: debitReason.trim(),
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setDebitMessage(messageFromApiBody(data, "Debit failed"));
        return;
      }
      setDebitMessage(`Debited. New balance (pesewas): ${data.balancePesewas ?? "ok"}.`);
    } catch {
      setDebitMessage("Request failed. Is the API running?");
    } finally {
      setDebitBusy(false);
    }
  }

  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Wallets</h1>
      <p className="mb-6 text-sm text-gray-600">
        <strong className="text-gray-900">Credit</strong> adds funds; <strong className="text-gray-900">debit</strong>{" "}
        removes funds from a user&apos;s in-app balance (e.g. fraud clawback). 1 GHS = 100 pesewas. Open from{" "}
        <strong className="text-gray-900">Users</strong> or <strong className="text-gray-900">Workers</strong> via
        &quot;Credit wallet&quot; to fill the user ID automatically.
      </p>
      {prefillLabel && (
        <GlassPanel className="mb-4 !py-3">
          <p className="text-sm text-gray-800">
            Crediting: <strong className="text-amber-800">{prefillLabel}</strong>
          </p>
        </GlassPanel>
      )}
      <div className="grid max-w-4xl gap-6 lg:grid-cols-2">
        <GlassPanel>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-wide text-gray-700">Credit wallet</h2>
          <form onSubmit={onCredit} className="space-y-4">
            <div>
              <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-gray-600">
                User ID (UUID)
              </label>
              <input
                required
                value={userId}
                onChange={(e) => setUserId(e.target.value)}
                placeholder="paste user id or use link from Users / Workers"
                className="admin-input"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-gray-600">
                Amount (GHS)
              </label>
              <input
                type="number"
                step="0.01"
                min="0.01"
                value={amountGhs}
                onChange={(e) => setAmountGhs(e.target.value)}
                className="admin-input"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-gray-600">
                Reason (audit)
              </label>
              <input
                required
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                className="admin-input"
              />
            </div>
            {message && (
              <p className="rounded-lg border border-amber-200/80 bg-amber-50 px-3 py-2 text-sm text-amber-900">
                {message}
              </p>
            )}
            <button type="submit" disabled={busy} className="admin-btn-primary w-full">
              {busy ? "Saving…" : "Credit wallet"}
            </button>
          </form>
        </GlassPanel>

        <GlassPanel>
          <h2 className="mb-4 text-sm font-bold uppercase tracking-wide text-gray-700">Debit wallet</h2>
          <p className="mb-4 text-xs text-gray-600">
            Removes balance up to what the user holds. Fails if insufficient funds.
          </p>
          <form onSubmit={onDebit} className="space-y-4">
            <div>
              <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-gray-600">
                Amount (GHS)
              </label>
              <input
                type="number"
                step="0.01"
                min="0.01"
                value={debitAmountGhs}
                onChange={(e) => setDebitAmountGhs(e.target.value)}
                className="admin-input"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-semibold uppercase tracking-wide text-gray-600">
                Reason (audit, min 3 chars)
              </label>
              <input
                required
                minLength={3}
                value={debitReason}
                onChange={(e) => setDebitReason(e.target.value)}
                className="admin-input"
              />
            </div>
            {debitMessage && (
              <p
                className={`rounded-lg border px-3 py-2 text-sm ${
                  debitMessage.startsWith("Debited")
                    ? "border-emerald-200/80 bg-emerald-50 text-emerald-900"
                    : "border-red-200/80 bg-red-50 text-red-900"
                }`}
              >
                {debitMessage}
              </p>
            )}
            <button type="submit" disabled={debitBusy} className="admin-btn-secondary w-full">
              {debitBusy ? "Submitting…" : "Debit wallet"}
            </button>
          </form>
        </GlassPanel>
      </div>
    </div>
  );
}

export default function AdminWalletsPage() {
  return (
    <Suspense fallback={<p className="text-gray-500">Loading…</p>}>
      <AdminWalletsContent />
    </Suspense>
  );
}
