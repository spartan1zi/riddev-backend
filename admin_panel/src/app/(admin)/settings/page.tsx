import { GlassPanel } from "@/components/GlassPanel";

export default function AdminSettingsPage() {
  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Settings</h1>
      <GlassPanel>
        <p className="text-sm text-gray-700">
          Commission defaults — <code className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs">AppSettings</code> model
        </p>
      </GlassPanel>
    </div>
  );
}
