import type {
  Prisma
} from "../../generated/prisma/client.js";

export interface MessageCursor {
  id: string;
  timestamp: Date;
}

export function beforeCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          lt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          lt:
            cursor.id
        }
      }
    ]
  };
}

export function afterCursorWhere(
  cursor: MessageCursor
): Prisma.MessageWhereInput {
  return {
    OR: [
      {
        timestamp: {
          gt:
            cursor.timestamp
        }
      },
      {
        timestamp:
          cursor.timestamp,
        id: {
          gt:
            cursor.id
        }
      }
    ]
  };
}

export const chronologicalOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "asc"
    },
    {
      id:
        "asc"
    }
  ];

export const reverseChronologicalOrder:
  Prisma.MessageOrderByWithRelationInput[] =
  [
    {
      timestamp:
        "desc"
    },
    {
      id:
        "desc"
    }
  ];
