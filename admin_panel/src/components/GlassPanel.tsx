import { cn } from "@/lib/cn";

type Props = {
  children: React.ReactNode;
  className?: string;
  dense?: boolean;
};

/** Frosted card — matches EOD Inventory `GlassPanel.vue` */
export function GlassPanel({ children, className, dense }: Props) {
  return (
    <div
      className={cn(
        "rounded-2xl border border-gray-200/80 bg-white/70 shadow-[0_8px_30px_rgba(0,0,0,0.06)] ring-1 ring-gray-900/5 backdrop-blur-md",
        "bg-gradient-to-br from-amber-500/[0.06] via-transparent to-transparent",
        dense ? "p-3" : "p-4 md:p-5",
        className
      )}
    >
      {children}
    </div>
  );
}
