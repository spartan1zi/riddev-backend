import { JobCategory } from "@prisma/client";

/** Every value in the Prisma `JobCategory` enum. */
export const ALL_JOB_CATEGORIES: JobCategory[] = Object.values(
  JobCategory
) as JobCategory[];
