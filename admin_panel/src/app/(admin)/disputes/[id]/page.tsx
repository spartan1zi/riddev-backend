"use client";

import { GlassPanel } from "@/components/GlassPanel";
import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";
import { getAdminToken } from "@/lib/auth";
import { DisputeChatControls } from "@/components/DisputeChatControls";
import { DisputeChatPanel } from "@/components/DisputeChatPanel";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { FormEvent, useCallback, useEffect, useState } from "react";

type DisputeDetail = {
  id: string;
  status: string;
  reason: string;
  resolution: string | null;
  adminNotes: string | null;
  evidencePhotos: string[];
  everyoneChannelEnabled: boolean;
  disputeChatLocked: boolean;
  createdAt: string;
  resolvedAt: string | null;
  job: {
    id: string;
    title: string;
    status: string;
    customer: { id: string; name: string; email: string };
    worker: { id: string; name: string; email: string } | null;
  };
  raisedBy: { id: string; name: string; email: string; role: string };
};

function SettleForm({
  dispute,
  onDone,
}: {
  dispute: DisputeDetail;
  onDone: () => void;
}) {
  const [outcome, setOutcome] = useState<"REFUND_CUSTOMER" | "PAY_WORKER">("REFUND_CUSTOMER");
  const [resolution, setResolution] = useState("");
  const [adminNotes, setAdminNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setMsg(null);
    setBusy(true);
    try {
      const res = await adminApiFetch(`/api/admin/disputes/${dispute.id}/settle`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          outcome,
          resolution: resolution.trim(),
          adminNotes: adminNotes.trim() || undefined,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setMsg(messageFromApiBody(data, "Settlement failed"));
        return;
      }
      setMsg("Resolved.");
      onDone();
    } catch {
      setMsg("Request failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-3">
      <div>
        <label className="mb-1 block text-xs font-semibold uppercase text-gray-600">Outcome</label>
        <select
          value={outcome}
          onChange={(e) => setOutcome(e.target.value as "REFUND_CUSTOMER" | "PAY_WORKER")}
          className="admin-input w-full max-w-full"
        >
          <option value="REFUND_CUSTOMER">Refund customer (escrow → customer wallet)</option>
          <option value="PAY_WORKER">Pay worker (release escrow to worker)</option>
        </select>
      </div>
      <div>
        <label className="mb-1 block text-xs font-semibold uppercase text-gray-600">
          Resolution (public / audit, min 10 chars)
        </label>
        <textarea
          required
          minLength={10}
          rows={3}
          value={resolution}
          onChange={(e) => setResolution(e.target.value)}
          placeholder="Explain the decision for the record."
          className="admin-input min-h-[80px] w-full max-w-full resize-y"
        />
      </div>
      <div>
        <label className="mb-1 block text-xs font-semibold uppercase text-gray-600">Internal notes (optional)</label>
        <input
          value={adminNotes}
          onChange={(e) => setAdminNotes(e.target.value)}
          className="admin-input w-full max-w-full"
        />
      </div>
      {msg && (
        <p
          className={`text-sm ${msg.startsWith("Resolved") ? "text-emerald-700" : "text-red-700"}`}
        >
          {msg}
        </p>
      )}
      <button type="submit" disabled={busy} className="admin-btn-primary">
        {busy ? "Submitting…" : "Apply settlement"}
      </button>
    </form>
  );
}

export default function AdminDisputeDetailPage() {
  const params = useParams();
  const router = useRouter();
  const id = typeof params.id === "string" ? params.id : "";
  const [dispute, setDispute] = useState<DisputeDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [chatRefreshKey, setChatRefreshKey] = useState(0);

  const load = useCallback(async () => {
    if (!id) {
      setError("Invalid dispute id.");
      setLoading(false);
      return;
    }
    if (!getAdminToken()) {
      setError("Not logged in.");
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await adminApiFetch(`/api/admin/disputes/${id}`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, `Failed (${res.status})`));
        setDispute(null);
        return;
      }
      setDispute(data.dispute ?? null);
    } catch {
      setError("Cannot reach API.");
      setDispute(null);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  const photos = Array.isArray(dispute?.evidencePhotos) ? dispute!.evidencePhotos : [];

  return (
    <div className="mx-auto w-full max-w-2xl pb-8">
      <div className="mb-6 flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={() => router.push("/disputes")}
          className="admin-btn-secondary"
        >
          ← Back to list
        </button>
        <Link href="/escrow" className="text-sm text-amber-800 underline-offset-2 hover:underline">
          Escrow holdings
        </Link>
      </div>

      {loading ? (
        <p className="text-gray-500">Loading…</p>
      ) : error ? (
        <GlassPanel className="!border-red-200 !from-red-500/5">
          <p className="text-sm text-red-800">{error}</p>
          <button type="button" onClick={() => void load()} className="admin-btn-secondary mt-3">
            Retry
          </button>
        </GlassPanel>
      ) : !dispute ? (
        <GlassPanel>
          <p className="text-sm text-gray-600">Dispute not found.</p>
        </GlassPanel>
      ) : (
        <div className="flex flex-col gap-5">
          <GlassPanel dense className="!shadow-sm">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0 flex-1">
                <h1 className="text-xl font-bold leading-snug tracking-tight text-gray-900 sm:text-2xl">
                  {dispute.job.title}
                </h1>
                <p className="mt-2 text-xs leading-relaxed text-gray-600 sm:text-sm">
                  <span
                    className={`mr-2 inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold sm:text-xs ${
                      dispute.status === "RESOLVED"
                        ? "bg-emerald-100 text-emerald-800"
                        : "bg-amber-100 text-amber-900"
                    }`}
                  >
                    {dispute.status}
                  </span>
                  <span className="block mt-1.5 sm:inline sm:mt-0">
                    Opened {new Date(dispute.createdAt).toLocaleString()}
                  </span>
                  <span className="block sm:inline">
                    {" "}
                    · Raised by {dispute.raisedBy.name} ({dispute.raisedBy.role})
                  </span>
                </p>
              </div>
              <button type="button" onClick={() => void load()} className="admin-btn-secondary shrink-0 self-start text-xs">
                Refresh
              </button>
            </div>
          </GlassPanel>

          <GlassPanel dense className="!shadow-sm">
            <h2 className="mb-3 text-xs font-bold uppercase tracking-wide text-gray-600">Parties</h2>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="rounded-xl border border-gray-200/90 bg-white/80 px-3 py-3 shadow-sm">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">Customer</div>
                <div className="mt-1 text-sm font-semibold text-gray-900">{dispute.job.customer.name}</div>
                <div className="mt-0.5 break-all text-xs text-gray-500">{dispute.job.customer.email}</div>
              </div>
              <div className="rounded-xl border border-gray-200/90 bg-white/80 px-3 py-3 shadow-sm">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">Worker</div>
                <div className="mt-1 text-sm font-semibold text-gray-900">{dispute.job.worker?.name ?? "—"}</div>
                <div className="mt-0.5 break-all text-xs text-gray-500">{dispute.job.worker?.email ?? ""}</div>
              </div>
            </div>
          </GlassPanel>

          <DisputeChatControls
            disputeId={dispute.id}
            everyoneChannelEnabled={dispute.everyoneChannelEnabled ?? false}
            disputeChatLocked={dispute.disputeChatLocked ?? false}
            onSaved={() => {
              void load();
              setChatRefreshKey((k) => k + 1);
            }}
          />

          <DisputeChatPanel disputeId={dispute.id} refreshKey={chatRefreshKey} />

          <GlassPanel dense className="!shadow-sm">
            <h2 className="mb-2 text-xs font-bold uppercase tracking-wide text-gray-600">Original reason</h2>
            <p className="whitespace-pre-wrap text-sm leading-relaxed text-gray-800">{dispute.reason}</p>
          </GlassPanel>

          {photos.length > 0 && (
            <GlassPanel dense className="!shadow-sm">
              <h2 className="mb-3 text-xs font-bold uppercase tracking-wide text-gray-600">
                Evidence photos ({photos.length})
              </h2>
              <div className="grid grid-cols-2 gap-2 sm:gap-3">
                {photos.map((url) => (
                  <a
                    key={url}
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="group block overflow-hidden rounded-lg border border-gray-200/90 bg-gray-100/80 shadow-sm transition hover:ring-2 hover:ring-amber-400/40"
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={url}
                      alt="Dispute evidence"
                      className="aspect-[4/3] h-auto w-full object-cover transition group-hover:opacity-95"
                    />
                  </a>
                ))}
              </div>
            </GlassPanel>
          )}

          {dispute.status === "RESOLVED" && dispute.resolution && (
            <GlassPanel dense className="!shadow-sm">
              <h2 className="mb-2 text-xs font-bold uppercase tracking-wide text-gray-600">Resolution</h2>
              <p className="whitespace-pre-wrap text-sm leading-relaxed text-gray-800">{dispute.resolution}</p>
              {dispute.resolvedAt && (
                <p className="mt-2 text-xs text-gray-500">{new Date(dispute.resolvedAt).toLocaleString()}</p>
              )}
            </GlassPanel>
          )}

          {dispute.status !== "RESOLVED" && (
            <GlassPanel dense className="!shadow-sm">
              <h2 className="mb-3 text-xs font-bold uppercase tracking-wide text-gray-600">Settle dispute</h2>
              <SettleForm dispute={dispute} onDone={() => void load()} />
            </GlassPanel>
          )}
        </div>
      )}
    </div>
  );
}
