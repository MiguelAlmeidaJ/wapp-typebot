import { prisma } from "../../lib/database.js";

export async function listCompanyMemberships(companyId: string) {
  return prisma.companyMembership.findMany({
    where: {
      companyId,
      isActive: true,
      user: {
        isActive: true
      }
    },
    include: {
      user: {
        select: {
          id: true,
          name: true,
          email: true
        }
      }
    },
    orderBy: {
      user: {
        name: "asc"
      }
    }
  });
}
