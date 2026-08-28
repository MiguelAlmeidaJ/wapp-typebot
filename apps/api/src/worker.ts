import { prisma } from "./lib/database.js";
import {
  closeMediaCaptureQueue
} from "./jobs/media-capture.queue.js";
import {
  createMediaCaptureWorker
} from "./jobs/media-capture.worker.js";
import {
  closeRealtimeTransport
} from "./modules/realtime/realtime.bus.js";

const worker =
  createMediaCaptureWorker();

console.info(
  "[jobs] Wapp media worker started"
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

  await worker.close();
  await closeMediaCaptureQueue();
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

worker.on(
  "error",
  error => {
    console.error(
      "[jobs] worker error",
      error
    );
  }
);
