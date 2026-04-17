"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { ArrowPathIcon, PaperAirplaneIcon, PhotoIcon } from "@heroicons/react/24/solid";

import { cn } from "@/lib/cn";
import { adminApiFetch } from "@/lib/adminApi";
import { messageFromApiBody } from "@/lib/apiError";

export type DisputeChannelTab = "ALL" | "ADMIN_CUSTOMER" | "ADMIN_WORKER";

export type DisputeThreadMessage = {
  id: string;
  body: string;
  imageUrls: string[];
  createdAt: string;
  channel?: DisputeChannelTab;
  sender: { id: string; name: string; email?: string; role: string };
};

type Props = {
  disputeId: string;
  /** Refreshed when parent reloads dispute detail */
  refreshKey?: number;
};

function avatarInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length >= 2) {
    return (parts[0]![0] + parts[1]![0]).toUpperCase();
  }
  return name.trim().slice(0, 2).toUpperCase() || "?";
}

function roleAvatarClass(role: string): string {
  switch (role) {
    case "ADMIN":
      return "bg-gradient-to-br from-[#ff9f43] to-[#ff6b35] text-white ring-2 ring-white shadow";
    case "CUSTOMER":
      return "bg-sky-500 text-white ring-2 ring-white shadow";
    case "WORKER":
      return "bg-emerald-500 text-white ring-2 ring-white shadow";
    default:
      return "bg-slate-400 text-white ring-2 ring-white shadow";
  }
}

export function DisputeChatPanel({ disputeId, refreshKey = 0 }: Props) {
  const [channelBuckets, setChannelBuckets] = useState<Record<
    DisputeChannelTab,
    DisputeThreadMessage[]
  > | null>(null);
  const [legacyMessages, setLegacyMessages] = useState<DisputeThreadMessage[]>([]);
  const [activeChannel, setActiveChannel] = useState<DisputeChannelTab>("ALL");
  const [text, setText] = useState("");
  const [pendingFiles, setPendingFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  /** Scroll only this element — never use scrollIntoView on inner nodes (it scrolls the whole page). */
  const messagesScrollRef = useRef<HTMLDivElement | null>(null);

  const messages =
    channelBuckets != null ? (channelBuckets[activeChannel] ?? []) : legacyMessages;

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await adminApiFetch(`/api/disputes/${disputeId}/messages`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, `Failed to load messages (${res.status})`));
        setChannelBuckets(null);
        setLegacyMessages([]);
        return;
      }
      if (data.channels && typeof data.channels === "object") {
        const c = data.channels as Record<string, DisputeThreadMessage[]>;
        setChannelBuckets({
          ALL: Array.isArray(c.ALL) ? c.ALL : [],
          ADMIN_CUSTOMER: Array.isArray(c.ADMIN_CUSTOMER) ? c.ADMIN_CUSTOMER : [],
          ADMIN_WORKER: Array.isArray(c.ADMIN_WORKER) ? c.ADMIN_WORKER : [],
        });
        setLegacyMessages([]);
      } else {
        setChannelBuckets(null);
        setLegacyMessages(Array.isArray(data.messages) ? data.messages : []);
      }
    } catch {
      setError("Cannot load messages.");
      setChannelBuckets(null);
      setLegacyMessages([]);
    } finally {
      setLoading(false);
    }
  }, [disputeId]);

  useEffect(() => {
    void load();
  }, [load, refreshKey]);

  useEffect(() => {
    setActiveChannel("ALL");
  }, [disputeId]);

  useEffect(() => {
    const t = setInterval(() => void load(), 4500);
    return () => clearInterval(t);
  }, [load]);

  useEffect(() => {
    const el = messagesScrollRef.current;
    if (!el) return;
    requestAnimationFrame(() => {
      el.scrollTo({ top: el.scrollHeight, behavior: "smooth" });
    });
  }, [messages.length, activeChannel]);

  const placeholderByChannel: Record<DisputeChannelTab, string> = {
    ALL: "Type your message…",
    ADMIN_CUSTOMER: "Message the customer only (private)…",
    ADMIN_WORKER: "Message the worker only (private)…",
  };

  const hintByChannel: Record<DisputeChannelTab, string> = {
    ALL: "Everyone on the dispute sees this thread.",
    ADMIN_CUSTOMER: "Only you and the customer.",
    ADMIN_WORKER: "Only you and the worker.",
  };

  const channelLabel: Record<DisputeChannelTab, string> = {
    ALL: "Everyone",
    ADMIN_CUSTOMER: "Customer",
    ADMIN_WORKER: "Worker",
  };

  async function uploadFiles(files: File[]): Promise<string[]> {
    if (files.length === 0) return [];
    const fd = new FormData();
    for (const f of files) {
      fd.append("photos", f);
    }
    const res = await adminApiFetch(`/api/uploads/dispute-evidence`, {
      method: "POST",
      body: fd,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(messageFromApiBody(data, "Image upload failed"));
    }
    const urls = data.urls;
    return Array.isArray(urls) ? urls.map((u: unknown) => String(u)) : [];
  }

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const t = text.trim();
    if (t.length === 0 && pendingFiles.length === 0) return;
    setSending(true);
    setError(null);
    try {
      let imageUrls: string[] = [];
      if (pendingFiles.length > 0) {
        imageUrls = await uploadFiles(pendingFiles);
      }
      const res = await adminApiFetch(`/api/disputes/${disputeId}/messages`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          body: t.length > 0 ? t : undefined,
          imageUrls,
          channel: activeChannel,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(messageFromApiBody(data, "Send failed"));
        return;
      }
      setText("");
      setPendingFiles([]);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Send failed");
    } finally {
      setSending(false);
    }
  }

  function onPickFiles(fs: FileList | null) {
    if (!fs?.length) return;
    const next = Array.from(fs).slice(0, 8);
    setPendingFiles((p) => [...p, ...next].slice(0, 8));
  }

  function removePending(i: number) {
    setPendingFiles((p) => p.filter((_, j) => j !== i));
  }

  return (
    <div className="flex min-h-[420px] flex-col overflow-hidden rounded-xl border border-gray-200/95 bg-white shadow-[0_4px_24px_rgba(15,23,42,0.06)]">
      {/* Header — template-style msg_head */}
      <div className="flex shrink-0 items-center gap-3 border-b border-gray-100 bg-white px-4 py-3.5">
        <div
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-[#ff9f43] to-[#ff6b35] text-sm font-bold text-white shadow-md ring-4 ring-orange-50"
          aria-hidden
        >
          RD
        </div>
        <div className="min-w-0 flex-1">
          <h2 className="truncate text-[15px] font-semibold leading-tight text-gray-900">
            Dispute messages
          </h2>
          <p className="mb-0 mt-0.5 text-xs text-gray-500">{hintByChannel[activeChannel]}</p>
        </div>
        <button
          type="button"
          onClick={() => void load()}
          className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-gray-200 bg-gray-50 text-gray-600 transition hover:bg-gray-100 hover:text-gray-900"
          title="Refresh"
        >
          <ArrowPathIcon className="h-4 w-4" />
        </button>
      </div>

      {/* Channel tabs — pill bar */}
      <div className="border-b border-gray-100 bg-[#f4f6f9] px-3 py-2.5">
        <div className="flex flex-wrap gap-1.5">
          {(
            [
              ["ALL", "Everyone"],
              ["ADMIN_CUSTOMER", "With customer"],
              ["ADMIN_WORKER", "With worker"],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              onClick={() => setActiveChannel(id)}
              className={cn(
                "rounded-full px-3 py-1.5 text-xs font-semibold transition",
                activeChannel === id
                  ? "bg-white text-gray-900 shadow-sm ring-1 ring-gray-200/80"
                  : "text-gray-600 hover:bg-white/70 hover:text-gray-900"
              )}
            >
              {label}
            </button>
          ))}
        </div>
        <p className="mt-2 text-[11px] text-gray-500">
          Thread: <span className="font-medium text-gray-700">{channelLabel[activeChannel]}</span>
        </p>
      </div>

      {error && (
        <p className="mx-3 mt-3 rounded-lg border border-red-100 bg-red-50 px-3 py-2 text-xs text-red-700">
          {error}
        </p>
      )}

      {/* Messages — template msg_card_body */}
      <div
        ref={messagesScrollRef}
        className="min-h-[240px] max-h-[min(52vh,360px)] flex-1 overflow-y-auto bg-[#eef1f4] px-3 py-4"
      >
        {loading ? (
          <div className="flex h-32 items-center justify-center">
            <div className="flex items-center gap-2 text-sm text-gray-500">
              <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-orange-400 border-t-transparent" />
              Loading messages…
            </div>
          </div>
        ) : messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 text-center">
            <p className="text-sm font-medium text-gray-600">No messages yet</p>
            <p className="mt-1 max-w-xs text-xs text-gray-500">
              Start the conversation below — photos are shared like in the mobile apps.
            </p>
          </div>
        ) : (
          <ul className="m-0 list-none space-y-4 p-0">
            {messages.map((m) => {
              const isAdmin = m.sender.role === "ADMIN";
              const timeStr = new Date(m.createdAt).toLocaleTimeString(undefined, {
                hour: "numeric",
                minute: "2-digit",
              });
              return (
                <li
                  key={m.id}
                  className={cn("flex w-full gap-2.5", isAdmin ? "flex-row-reverse" : "flex-row")}
                >
                  <div
                    className={cn(
                      "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[11px] font-bold",
                      roleAvatarClass(m.sender.role)
                    )}
                    title={`${m.sender.name} (${m.sender.role})`}
                  >
                    {avatarInitials(m.sender.name)}
                  </div>
                  <div
                    className={cn(
                      "flex min-w-0 max-w-[min(92%,28rem)] flex-col",
                      isAdmin ? "items-end" : "items-start"
                    )}
                  >
                    {!isAdmin && (
                      <span className="mb-1 px-0.5 text-[11px] font-semibold text-gray-600">
                        {m.sender.name}{" "}
                        <span className="font-normal text-gray-400">({m.sender.role})</span>
                      </span>
                    )}
                    <div
                      className={cn(
                        "rounded-2xl px-3.5 py-2.5 shadow-sm",
                        isAdmin
                          ? "rounded-br-md bg-gradient-to-br from-[#ff9f43] to-[#ff7324] text-white"
                          : "rounded-bl-md border border-gray-100/80 bg-white text-gray-900"
                      )}
                    >
                      {m.body && m.body !== "(Images attached)" && (
                        <p className="m-0 whitespace-pre-wrap text-[13px] leading-relaxed">{m.body}</p>
                      )}
                      {(m.imageUrls?.length ?? 0) > 0 && (
                        <div
                          className={cn(
                            "mt-2 flex flex-wrap gap-2",
                            isAdmin && m.body && m.body !== "(Images attached)" && "pt-0.5"
                          )}
                        >
                          {(m.imageUrls ?? []).map((u) => (
                            <a
                              key={u}
                              href={u}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="group relative overflow-hidden rounded-lg border border-white/20 shadow-sm"
                            >
                              {/* eslint-disable-next-line @next/next/no-img-element */}
                              <img
                                src={u}
                                alt=""
                                className="h-[4.5rem] w-[4.5rem] object-cover transition group-hover:opacity-95 sm:h-24 sm:w-24"
                              />
                              <span className="absolute inset-x-0 bottom-0 bg-black/40 py-0.5 text-center text-[10px] text-white opacity-0 transition group-hover:opacity-100">
                                Open
                              </span>
                            </a>
                          ))}
                        </div>
                      )}
                    </div>
                    <ul className="mt-1.5 list-none p-0">
                      <li className="text-[11px] text-gray-400">{timeStr}</li>
                    </ul>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {pendingFiles.length > 0 && (
        <div className="flex flex-wrap gap-2 border-t border-gray-100 bg-[#fafbfc] px-3 py-2">
          {pendingFiles.map((f, i) => (
            <span
              key={`${f.name}-${i}`}
              className="inline-flex items-center gap-1.5 rounded-full border border-amber-200/80 bg-amber-50 px-2.5 py-1 text-[11px] font-medium text-amber-950"
            >
              {f.name.slice(0, 28)}
              <button
                type="button"
                className="rounded-full p-0.5 hover:bg-amber-200/60"
                onClick={() => removePending(i)}
                aria-label="Remove"
              >
                ×
              </button>
            </span>
          ))}
        </div>
      )}

      {/* Footer — template card-footer + input group */}
      <form
        onSubmit={send}
        className="shrink-0 border-t border-gray-200 bg-white p-3 pt-2.5"
      >
        <div className="flex items-end gap-2 rounded-2xl border border-gray-200 bg-[#f8f9fb] p-1.5 pl-2 shadow-inner focus-within:border-orange-300 focus-within:ring-1 focus-within:ring-orange-200/80">
          <label className="mb-1.5 flex h-9 w-9 shrink-0 cursor-pointer items-center justify-center rounded-xl text-gray-500 transition hover:bg-white hover:text-orange-500">
            <PhotoIcon className="h-5 w-5" />
            <input
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif"
              multiple
              className="sr-only"
              onChange={(e) => {
                onPickFiles(e.target.files);
                e.target.value = "";
              }}
            />
          </label>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={placeholderByChannel[activeChannel]}
            rows={2}
            className="max-h-36 min-h-[44px] flex-1 resize-y border-0 bg-transparent py-2 text-[13px] text-gray-900 placeholder:text-gray-400 focus:outline-none focus:ring-0"
          />
          <button
            type="submit"
            disabled={sending}
            className="mb-1 inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-[#ff9f43] to-[#ff7324] text-white shadow-md transition hover:brightness-105 disabled:opacity-50"
            title="Send"
          >
            {sending ? (
              <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
            ) : (
              <PaperAirplaneIcon className="h-5 w-5 -rotate-12" />
            )}
          </button>
        </div>
      </form>
    </div>
  );
}
