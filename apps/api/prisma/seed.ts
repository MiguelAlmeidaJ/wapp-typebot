import "dotenv/config";

import { prisma } from "../src/lib/database.js";
import { hashPassword } from "../src/lib/password.js";

function required(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`${name} is required to seed the database.`);
  }

  return value;
}

async function main() {
  const companyName = required("SEED_COMPANY_NAME");
  const companySlug = required("SEED_COMPANY_SLUG").toLowerCase();
  const adminName = required("SEED_ADMIN_NAME");
  const adminEmail = required("SEED_ADMIN_EMAIL").toLowerCase();
  const adminPassword = required("SEED_ADMIN_PASSWORD");

  if (
    adminPassword.toLowerCase().includes("change-me") ||
    adminPassword.length < 12
  ) {
    throw new Error(
      "SEED_ADMIN_PASSWORD must be changed and contain at least 12 characters."
    );
  }

  const company = await prisma.company.upsert({
    where: {
      slug: companySlug
    },
    update: {
      name: companyName,
      status: "ACTIVE"
    },
    create: {
      name: companyName,
      slug: companySlug
    }
  });

  const existingUser = await prisma.user.findUnique({
    where: {
      email: adminEmail
    }
  });

  const user = existingUser
    ? await prisma.user.update({
        where: {
          id: existingUser.id
        },
        data: {
          name: adminName,
          isActive: true
        }
      })
    : await prisma.user.create({
        data: {
          name: adminName,
          email: adminEmail,
          passwordHash: await hashPassword(adminPassword)
        }
      });

  await prisma.companyMembership.upsert({
    where: {
      companyId_userId: {
        companyId: company.id,
        userId: user.id
      }
    },
    update: {
      role: "OWNER",
      isActive: true
    },
    create: {
      companyId: company.id,
      userId: user.id,
      role: "OWNER"
    }
  });

  console.log(`Seed complete: ${adminEmail} -> ${company.slug} (OWNER)`);
}

main()
  .catch(error => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
