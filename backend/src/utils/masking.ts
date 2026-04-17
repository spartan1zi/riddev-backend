import type { JobStatus } from "@prisma/client";

/** Mask worker for customer until they have committed (accepted quote or work underway). */
export function maskWorkerName(fullName: string, jobStatus: JobStatus | null): string {
  if (!jobStatus) return maskName(fullName);
  if (
    jobStatus === "ACCEPTED" ||
    jobStatus === "IN_PROGRESS" ||
    jobStatus === "COMPLETED" ||
    jobStatus === "DISPUTED"
  ) {
    return fullName;
  }
  return maskName(fullName);
}

function maskName(fullName: string): string {
  const parts = fullName.trim().split(/\s+/);
  if (parts.length === 0) return "";
  if (parts.length === 1) return parts[0].charAt(0) + ".";
  const first = parts[0];
  const last = parts[parts.length - 1];
  return `${first} ${last.charAt(0)}.`;
}
