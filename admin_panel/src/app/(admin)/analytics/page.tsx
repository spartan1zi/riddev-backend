"use client";

import { GlassPanel } from "@/components/GlassPanel";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";

const sample = [
  { day: "Mon", jobs: 4 },
  { day: "Tue", jobs: 7 },
  { day: "Wed", jobs: 5 },
  { day: "Thu", jobs: 9 },
  { day: "Fri", jobs: 12 },
];

export default function AnalyticsPage() {
  return (
    <div>
      <h1 className="mb-2 text-2xl font-bold tracking-tight text-gray-900">Analytics</h1>
      <p className="mb-6 text-sm text-gray-600">Operational metrics — sample chart until API aggregates are wired.</p>
      <GlassPanel className="min-h-[320px] w-full min-w-0">
        <div className="h-80 w-full min-w-0">
          <ResponsiveContainer width="100%" height="100%" minHeight={280}>
            <BarChart data={sample}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis dataKey="day" stroke="#64748b" fontSize={12} />
              <YAxis stroke="#64748b" fontSize={12} />
              <Tooltip
                contentStyle={{
                  background: "rgba(255,255,255,0.95)",
                  border: "1px solid rgba(245,158,11,0.35)",
                  borderRadius: "12px",
                  boxShadow: "0 8px 30px rgba(0,0,0,0.08)",
                }}
              />
              <Bar dataKey="jobs" fill="#f59e0b" radius={[6, 6, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
        <p className="mt-4 text-xs text-gray-500">Sample data — replace with API aggregates.</p>
      </GlassPanel>
    </div>
  );
}
