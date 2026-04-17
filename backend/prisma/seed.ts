import { PrismaClient, UserRole } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  const email = process.env.ADMIN_EMAIL ?? "admin@riddev.local";
  const password = process.env.ADMIN_PASSWORD ?? "adminadmin";
  const phone = process.env.ADMIN_PHONE ?? "+233000000001";
  const passwordHash = await bcrypt.hash(password, 12);

  await prisma.user.upsert({
    where: { email },
    create: {
      name: "RidDev Admin",
      email,
      phone,
      passwordHash,
      role: UserRole.ADMIN,
    },
    update: {
      passwordHash,
      role: UserRole.ADMIN,
    },
  });

  console.log(`Admin user ready: ${email} (password from ADMIN_PASSWORD or default: adminadmin)`);
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
