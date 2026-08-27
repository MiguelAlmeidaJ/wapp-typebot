import { prisma } from "../lib/database.js";

async function main() {
  const tickets =
    await prisma.ticket.findMany({
      select: {
        id: true,
        status: true
      },
      orderBy: {
        createdAt: "asc"
      }
    });

  let updated = 0;

  for (const ticket of tickets) {
    const [
      firstInbound,
      lastInbound,
      lastOutbound
    ] = await Promise.all([
      prisma.message.findFirst({
        where: {
          ticketId:
            ticket.id,
          direction:
            "INBOUND"
        },
        select: {
          timestamp: true
        },
        orderBy: {
          timestamp: "asc"
        }
      }),
      prisma.message.findFirst({
        where: {
          ticketId:
            ticket.id,
          direction:
            "INBOUND"
        },
        select: {
          timestamp: true
        },
        orderBy: {
          timestamp: "desc"
        }
      }),
      prisma.message.findFirst({
        where: {
          ticketId:
            ticket.id,
          direction:
            "OUTBOUND"
        },
        select: {
          timestamp: true
        },
        orderBy: {
          timestamp: "desc"
        }
      })
    ]);

    const firstResponse =
      firstInbound
        ? await prisma.message.findFirst({
            where: {
              ticketId:
                ticket.id,
              direction:
                "OUTBOUND",
              timestamp: {
                gte:
                  firstInbound.timestamp
              }
            },
            select: {
              timestamp: true
            },
            orderBy: {
              timestamp: "asc"
            }
          })
        : null;

    const waitingSince =
      ticket.status !== "CLOSED" &&
      lastInbound &&
      (
        !lastOutbound ||
        lastInbound.timestamp >
          lastOutbound.timestamp
      )
        ? lastInbound.timestamp
        : null;

    await prisma.ticket.update({
      where: {
        id: ticket.id
      },
      data: {
        firstInboundAt:
          firstInbound?.timestamp ??
          null,
        firstResponseAt:
          firstResponse?.timestamp ??
          null,
        lastInboundAt:
          lastInbound?.timestamp ??
          null,
        lastOutboundAt:
          lastOutbound?.timestamp ??
          null,
        waitingSince
      }
    });

    updated += 1;

    if (
      updated % 50 === 0
    ) {
      console.log(
        `[SLA] ${updated}/${tickets.length} tickets`
      );
    }
  }

  console.log(
    `[SLA] Backfill complete: ${updated} ticket(s).`
  );
}

main()
  .catch(error => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
