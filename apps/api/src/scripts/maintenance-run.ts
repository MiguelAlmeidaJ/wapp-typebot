import { prisma } from "../lib/database.js";
import { runMaintenance } from "../jobs/maintenance.service.js";

try {
  const result =
    await runMaintenance(
      "CLI"
    );

  console.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );
} catch (error) {
  console.error(
    "[maintenance] CLI run failed:",
    error instanceof Error
      ? error.message
      : error
  );

  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
