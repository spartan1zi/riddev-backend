"use client";

import { useState } from "react";

import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";

type Props = {
  disputeId: string;
  everyoneChannelEnabled: boolean;
  disputeChatLocked: boolean;
  onSaved: () => void;
};

export function DisputeChatControls({
  disputeId,
  everyoneChannelEnabled,
  disputeChatLocked,
  onSaved,
}: Props) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function patch(body: Record<string, boolean>) {
    setError(null);
    setBusy(true);
    try {
      const res = await adminApiFetch(`/api/admin/disputes/${disputeId}/chat-settings`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, "Update failed"));
        return;
      }
      onSaved();
    } catch {
      setError("Request failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="rounded-xl border border-gray-200/90 bg-white p-4 shadow-sm">
      <h2 className="mb-1 text-xs font-bold uppercase tracking-wide text-gray-600">
        Dispute chat controls
      </h2>
      <p className="mb-4 text-[11px] leading-snug text-gray-500">
        Customers and workers start in private threads only. Open the Everyone channel when you are ready
        for group messages. Full lock stops all parties (except admins) from sending in every thread.
      </p>

      {error && (
        <p className="mb-3 rounded-lg bg-red-50 px-2 py-1.5 text-xs text-red-700">{error}</p>
      )}

      <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap">
        <button
          type="button"
          disabled={busy || disputeChatLocked}
          onClick={() =>
            void patch({ everyoneChannelEnabled: !everyoneChannelEnabled })
          }
          className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-2.5 text-left text-sm font-semibold text-amber-950 shadow-sm transition hover:bg-amber-100 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {everyoneChannelEnabled ? "Disable Everyone channel" : "Enable Everyone channel"}
          <span className="mt-0.5 block text-[11px] font-normal text-amber-900/80">
            {everyoneChannelEnabled
              ? "Customer & worker can no longer post in Everyone (they can still read)."
              : "Allow customer & worker to read and write in Everyone."}
          </span>
        </button>

        <button
          type="button"
          disabled={busy}
          onClick={() => void patch({ disputeChatLocked: !disputeChatLocked })}
          className="rounded-lg border border-slate-200 bg-slate-50 px-4 py-2.5 text-left text-sm font-semibold text-slate-900 shadow-sm transition hover:bg-slate-100"
        >
          {disputeChatLocked ? "Unlock dispute chat" : "Lock entire dispute chat"}
          <span className="mt-0.5 block text-[11px] font-normal text-slate-600">
            {disputeChatLocked
              ? "Let parties message again (respects Everyone on/off above)."
              : "Freeze all channels for customer & worker; you can still reply as admin."}
          </span>
        </button>
      </div>

      {disputeChatLocked && (
        <p className="mt-3 text-[11px] text-amber-800">
          Everyone channel toggle is disabled while the dispute is fully locked. Unlock first to change who
          can post in Everyone.
        </p>
      )}
    </div>
  );
}
