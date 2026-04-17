"use client";

import { AdminNav } from "@/components/AdminNav";
import { getAdminToken } from "@/lib/auth";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

export default function AdminShellLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const t = getAdminToken();
    if (!t) {
      router.replace("/login");
      return;
    }
    setReady(true);
  }, [router]);

  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-gray-100 via-gray-50 to-amber-50/30 text-gray-600">
        <div className="flex flex-col items-center gap-3 rounded-2xl border border-gray-200/80 bg-white/70 px-10 py-8 shadow-glass backdrop-blur-md">
          <div className="h-10 w-10 animate-spin rounded-full border-2 border-amber-500 border-t-transparent" />
          <p className="text-sm font-medium text-gray-700">Loading admin…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-[100dvh] max-h-[100dvh] w-full overflow-hidden bg-gradient-to-br from-gray-100 via-gray-50 to-amber-50/30 text-gray-900">
      <AdminNav />
      <div className="relative z-10 flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden pt-14 md:pt-0">
        <header className="relative z-20 flex min-h-[3.25rem] shrink-0 items-center border-b border-gray-200/80 bg-white/50 px-4 py-3 shadow-[0_8px_30px_rgba(0,0,0,0.06)] backdrop-blur-md md:pl-8 md:pr-8">
          <h1 className="pl-12 text-lg font-semibold tracking-tight text-gray-900 md:pl-0">
            RidDev <span className="text-amber-600">Admin</span>
          </h1>
        </header>
        <main className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-6 animate-page-in md:px-8">
          {children}
        </main>
        <footer
          className="shrink-0 border-t border-gray-200/80 bg-white/40 px-4 py-2.5 text-center text-[11px] text-gray-500 backdrop-blur-sm md:px-8"
          role="contentinfo"
        >
          RidDev Services — administration panel
        </footer>
      </div>
    </div>
  );
}
