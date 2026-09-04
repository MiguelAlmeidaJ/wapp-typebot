import type { AutomationActionTypeValue } from "./automation.service.js";

export type AutomationActionDecision =
  | "EXECUTE"
  | "SKIP_CHATBOT_TEXT";

export function automationActionDecision(input: {
  actionType: AutomationActionTypeValue;
  chatbotHandledSourceMessage: boolean;
  hasActiveChatbotSession: boolean;
}): AutomationActionDecision {
  if (
    input.actionType === "SEND_TEXT" &&
    (
      input.chatbotHandledSourceMessage ||
      input.hasActiveChatbotSession
    )
  ) {
    return "SKIP_CHATBOT_TEXT";
  }

  return "EXECUTE";
}
