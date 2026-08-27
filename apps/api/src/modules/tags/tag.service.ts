import { AppError } from "../../errors/app-error.js";
import { prisma } from "../../lib/database.js";
import { publishRealtime } from "../realtime/realtime.bus.js";

export const tagColorKeys = [
  "GREEN",
  "BLUE",
  "ORANGE",
  "RED",
  "PURPLE",
  "GRAY"
] as const;

export async function listTags(input: {
  companyId: string;
  includeInactive?: boolean;
}) {
  return prisma.tag.findMany({
    where: {
      companyId: input.companyId,
      ...(input.includeInactive
        ? {}
        : {
            isActive: true
          })
    },
    orderBy: [
      {
        isActive: "desc"
      },
      {
        name: "asc"
      }
    ],
    take: 200
  });
}

export async function createTag(input: {
  companyId: string;
  name: string;
  colorKey: typeof tagColorKeys[number];
}) {
  const name = input.name.trim();

  const existing =
    await prisma.tag.findFirst({
      where: {
        companyId: input.companyId,
        name
      },
      select: {
        id: true
      }
    });

  if (existing) {
    throw new AppError(
      "Já existe uma etiqueta com este nome.",
      409,
      "TAG_NAME_IN_USE"
    );
  }

  const tag =
    await prisma.tag.create({
      data: {
        companyId:
          input.companyId,
        name,
        colorKey:
          input.colorKey
      }
    });

  publishRealtime(
    input.companyId,
    {
      type: "tag.updated",
      tagId: tag.id
    }
  );

  return tag;
}

export async function updateTag(input: {
  companyId: string;
  tagId: string;
  name?: string;
  colorKey?: typeof tagColorKeys[number];
  isActive?: boolean;
}) {
  const existing =
    await prisma.tag.findFirst({
      where: {
        id: input.tagId,
        companyId:
          input.companyId
      }
    });

  if (!existing) {
    throw new AppError(
      "Etiqueta não encontrada.",
      404,
      "TAG_NOT_FOUND"
    );
  }

  const name =
    input.name?.trim();

  if (
    name &&
    name !== existing.name
  ) {
    const duplicate =
      await prisma.tag.findFirst({
        where: {
          companyId:
            input.companyId,
          name,
          id: {
            not: existing.id
          }
        },
        select: {
          id: true
        }
      });

    if (duplicate) {
      throw new AppError(
        "Já existe uma etiqueta com este nome.",
        409,
        "TAG_NAME_IN_USE"
      );
    }
  }

  const tag =
    await prisma.tag.update({
      where: {
        id: existing.id
      },
      data: {
        ...(name !== undefined
          ? { name }
          : {}),
        ...(input.colorKey !== undefined
          ? {
              colorKey:
                input.colorKey
            }
          : {}),
        ...(input.isActive !== undefined
          ? {
              isActive:
                input.isActive
            }
          : {})
      }
    });

  publishRealtime(
    input.companyId,
    {
      type: "tag.updated",
      tagId: tag.id
    }
  );

  return tag;
}
