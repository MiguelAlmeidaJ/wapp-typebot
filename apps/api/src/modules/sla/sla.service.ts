import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export async function getSlaSettings(
  companyId: string
) {
  const company =
    await prisma.company.findUnique({
      where: {
        id: companyId
      },
      select: {
        id: true,
        firstResponseSlaMinutes:
          true,
        replySlaMinutes:
          true
      }
    });

  if (!company) {
    throw new AppError(
      "Empresa não encontrada.",
      404,
      "COMPANY_NOT_FOUND"
    );
  }

  return company;
}

export async function updateSlaSettings(input: {
  companyId: string;
  firstResponseSlaMinutes: number;
  replySlaMinutes: number;
}) {
  const company =
    await prisma.company.update({
      where: {
        id: input.companyId
      },
      data: {
        firstResponseSlaMinutes:
          input.firstResponseSlaMinutes,
        replySlaMinutes:
          input.replySlaMinutes
      },
      select: {
        id: true,
        firstResponseSlaMinutes:
          true,
        replySlaMinutes:
          true
      }
    });

  publishRealtime(
    input.companyId,
    {
      type: "sla.updated"
    }
  );

  return company;
}
