import { prisma } from "../lib/database.js";

try {
  const now =
    new Date();

  const result =
    await prisma.session.updateMany({
      where: {
        revokedAt: null
      },
      data: {
        revokedAt:
          now
      }
    });

  console.log(
    `[security] Revoked ${result.count} active session(s).`
  );

  console.log(
    "[security] All users must sign in again."
  );
} catch (error) {
  console.error(
    "[security] Session revocation failed:",
    error instanceof Error
      ? error.message
      : error
  );

  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
