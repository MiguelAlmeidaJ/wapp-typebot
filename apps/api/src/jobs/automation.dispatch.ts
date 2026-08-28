import { env } from "../config/env.js";
import {
  evaluateAutomationEvent
} from "../modules/automations/automation.service.js";
import {
  type AutomationJobData,
  enqueueAutomationEvaluation
} from "./automation.queue.js";

export function scheduleAutomationEvaluation(
  data:
    AutomationJobData
) {
  if (env.REDIS_URL) {
    void enqueueAutomationEvaluation(
      data
    ).catch(
      error => {
        console.error(
          "[automations] enqueue failed",
          error
        );
      }
    );

    return;
  }

  /*
   * Local development fallback only. Production P1 baseline has Redis.
   * This preserves functionality without pretending the fallback is durable.
   */
  void evaluateAutomationEvent(
    data
  ).catch(
    error => {
      console.error(
        "[automations] inline evaluation failed",
        error
      );
    }
  );
}
