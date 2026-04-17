import type { User, WorkerProfile, JobStatus } from "@prisma/client";
import { maskWorkerName } from "../utils/masking";

export function serializeWorkerPublic(
  user: User & { workerProfile: WorkerProfile | null },
  options: {
    jobStatus: JobStatus | null;
    viewerIsCustomer: boolean;
    /** Customer comparing quotes sees full legal-style name. */
    revealFullName?: boolean;
  }
) {
  const maskForCustomer =
    options.viewerIsCustomer &&
    user.workerProfile &&
    !options.revealFullName;
  const name = maskForCustomer
    ? maskWorkerName(user.name, options.jobStatus)
    : user.name;
  const showPhone =
    options.jobStatus === "IN_PROGRESS" ||
    options.jobStatus === "COMPLETED" ||
    options.jobStatus === "DISPUTED";
  return {
    id: user.id,
    name,
    profilePhoto: user.profilePhoto,
    rating: user.workerProfile?.rating ?? 0,
    totalJobsCompleted: user.workerProfile?.totalJobsCompleted ?? 0,
    tier: user.workerProfile?.tier,
    bio: user.workerProfile?.bio,
    serviceCategories: user.workerProfile?.serviceCategories ?? [],
    baseLocationLat: user.workerProfile?.baseLocationLat,
    baseLocationLng: user.workerProfile?.baseLocationLng,
    phone: showPhone ? user.phone : null,
  };
}
