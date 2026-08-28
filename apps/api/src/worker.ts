import { prisma } from "./lib/database.js";
import {
  createAutomationWorker
} from "./jobs/automation.worker.js";
import {
  closeAutomationQueue
} from "./jobs/automation.queue.js";
import {
  closeMediaCaptureQueue
} from "./jobs/media-capture.queue.js";
import {
  createMediaCaptureWorker
} from "./jobs/media-capture.worker.js";
import {
  closeMaintenanceQueue,
  ensureMaintenanceSchedule
} from "./jobs/maintenance.queue.js";
import {
  createMaintenanceWorker
} from "./jobs/maintenance.worker.js";
import {
  closeRealtimeTransport
} from "./modules/realtime/realtime.bus.js";

const workers = [
  createMediaCaptureWorker(),
  createMaintenanceWorker(),
  createAutomationWorker()
];

await ensureMaintenanceSchedule();

console.info(
  "[jobs] Wapp workers started",
  {
    workers:
      workers.length
  }
);

let shuttingDown =
  false;

async function shutdown(
  signal: string
) {
  if (shuttingDown) {
    return;
  }

  shuttingDown =
    true;

  console.info(
    `[jobs] shutting down (${signal})`
  );

  await Promise.all(
    workers.map(
      worker =>
        worker.close()
    )
  );

  await Promise.all([
    closeMediaCaptureQueue(),
    closeMaintenanceQueue(),
    closeAutomationQueue()
  ]);

  await closeRealtimeTransport();
  await prisma.$disconnect();

  process.exit(0);
}

process.on(
  "SIGINT",
  () => {
    void shutdown(
      "SIGINT"
    );
  }
);

process.on(
  "SIGTERM",
  () => {
    void shutdown(
      "SIGTERM"
    );
  }
);

for (
  const worker
  of workers
) {
  worker.on(
    "error",
    error => {
      console.error(
        "[jobs] worker error",
        error
      );
    }
  );
}
