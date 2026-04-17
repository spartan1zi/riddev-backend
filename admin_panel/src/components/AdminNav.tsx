"use client";

import { clearAdminSession } from "@/lib/auth";
import { cn } from "@/lib/cn";
import {
  BanknotesIcon,
  Bars3Icon,
  ChartBarIcon,
  ClipboardDocumentListIcon,
  Cog6ToothIcon,
  ExclamationTriangleIcon,
  LockClosedIcon,
  HomeIcon,
  UserGroupIcon,
  UsersIcon,
  WalletIcon,
  XMarkIcon,
} from "@heroicons/react/24/outline";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";

const links: { href: string; label: string; Icon: React.ComponentType<{ className?: string }> }[] = [
  { href: "/dashboard", label: "Dashboard", Icon: HomeIcon },
  { href: "/users", label: "Users", Icon: UsersIcon },
  { href: "/workers", label: "Workers", Icon: UserGroupIcon },
  { href: "/jobs", label: "Jobs", Icon: ClipboardDocumentListIcon },
  { href: "/escrow", label: "Escrow", Icon: LockClosedIcon },
  { href: "/disputes", label: "Disputes", Icon: ExclamationTriangleIcon },
  { href: "/payments", label: "Payments", Icon: BanknotesIcon },
  { href: "/wallets", label: "Wallets", Icon: WalletIcon },
  { href: "/analytics", label: "Analytics", Icon: ChartBarIcon },
  { href: "/settings", label: "Settings", Icon: Cog6ToothIcon },
];

function pathActive(pathname: string, href: string) {
  if (href === "/dashboard") return pathname === "/dashboard";
  return pathname === href || pathname.startsWith(`${href}/`);
}

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();

  return (
    <ul className="space-y-1 uppercase tracking-wide">
      {links.map(({ href, label, Icon }) => {
        const active = pathActive(pathname, href);
        return (
          <li key={href}>
            <Link
              href={href}
              onClick={onNavigate}
              className={cn(
                "relative flex items-center gap-3 overflow-hidden rounded-xl px-3 py-2.5 text-xs font-semibold transition-all duration-200",
                active
                  ? "bg-gradient-to-r from-amber-500/25 to-amber-500/5 text-amber-900 shadow-[0_0_20px_rgba(245,158,11,0.18)]"
                  : "text-gray-700 hover:bg-white/60 hover:shadow-[0_0_16px_rgba(245,158,11,0.08)]"
              )}
            >
              {active && (
                <span className="absolute bottom-2 left-0 top-2 w-0.5 rounded-full bg-amber-500 shadow-[0_0_10px_rgba(245,158,11,0.9)]" />
              )}
              <Icon
                className={cn(
                  "h-5 w-5 shrink-0",
                  active ? "text-amber-600" : "text-gray-500"
                )}
              />
              <span>{label}</span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

function SidebarBody({ onNavigate }: { onNavigate?: () => void }) {
  const router = useRouter();

  function logout() {
    clearAdminSession();
    router.replace("/login");
  }

  return (
    <>
      <div className="shrink-0 border-b border-gray-200/80 px-4 py-4">
        <div className="text-sm font-semibold uppercase tracking-wide text-amber-600">RidDev</div>
        <div className="mt-0.5 text-xs font-medium uppercase tracking-wide text-gray-500">Admin console</div>
      </div>
      <nav className="min-h-0 flex-1 space-y-1 overflow-y-auto overscroll-contain p-2">
        <NavLinks onNavigate={onNavigate} />
      </nav>
      <div className="shrink-0 border-t border-gray-200/80 p-2">
        <button
          type="button"
          onClick={logout}
          className="w-full rounded-xl px-3 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-gray-600 transition hover:bg-amber-500/10 hover:text-amber-900"
        >
          Log out
        </button>
      </div>
    </>
  );
}

export function AdminNav() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  return (
    <>
      {/* Mobile overlay */}
      <button
        type="button"
        aria-label="Open menu"
        className="fixed left-4 top-3 z-40 rounded-xl border border-gray-200/80 bg-white/80 p-2 text-gray-700 shadow-md backdrop-blur-md md:hidden"
        onClick={() => setMobileOpen(true)}
      >
        <Bars3Icon className="h-6 w-6" />
      </button>

      {mobileOpen && (
        <div
          className="fixed inset-0 z-40 bg-gray-900/50 backdrop-blur-sm md:hidden"
          aria-hidden
          onClick={() => setMobileOpen(false)}
        />
      )}

      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex h-full w-[min(18rem,calc(100vw-1rem))] flex-col overflow-hidden border-r border-gray-200/80 bg-white/95 shadow-2xl backdrop-blur-xl transition-transform duration-300 ease-out md:hidden",
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
        <div className="flex shrink-0 items-center justify-between border-b border-gray-200/80 px-3 py-3 md:hidden">
          <span className="text-sm font-semibold text-gray-900">Menu</span>
          <button
            type="button"
            aria-label="Close menu"
            className="rounded-xl border border-gray-200/80 bg-white/60 p-1.5 text-gray-600 transition hover:bg-amber-500/10 hover:text-amber-800"
            onClick={() => setMobileOpen(false)}
          >
            <XMarkIcon className="h-5 w-5" />
          </button>
        </div>
        <SidebarBody onNavigate={() => setMobileOpen(false)} />
      </aside>

      {/* Desktop sidebar */}
      <aside className="relative z-30 hidden h-full w-[15.5rem] shrink-0 flex-col overflow-hidden border-r border-gray-200/80 bg-white/75 shadow-[8px_0_40px_rgba(0,0,0,0.06)] backdrop-blur-xl md:flex">
        <SidebarBody />
      </aside>
    </>
  );
}
