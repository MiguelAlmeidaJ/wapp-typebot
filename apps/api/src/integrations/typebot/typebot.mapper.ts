import type { ChatbotOutput } from "./typebot.types.js";

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function richTextValue(value: unknown): string {
  if (typeof value === "string") return value;

  if (Array.isArray(value)) {
    return value
      .map(richTextValue)
      .filter(Boolean)
      .join("\n");
  }

  const node = objectValue(value);
  if (!node) return "";
  if (typeof node.text === "string") return node.text;

  const children = Array.isArray(node.children)
    ? node.children.map(richTextValue).join("")
    : "";

  if (typeof node.url === "string" && children) {
    return `${children} (${node.url})`;
  }

  return children;
}

function bubbleText(value: unknown): string | undefined {
  const bubble = objectValue(value);
  const content = objectValue(bubble?.content);

  if (bubble?.type === "text") {
    if (content?.type === "markdown" && typeof content.markdown === "string") {
      return content.markdown.trim() || undefined;
    }

    if (content?.type === "richText") {
      return richTextValue(content.richText).trim() || undefined;
    }
  }

  if (
    ["image", "video", "audio"].includes(String(bubble?.type)) &&
    typeof content?.url === "string"
  ) {
    return content.url;
  }

  return undefined;
}

function choiceLabel(value: unknown): string | undefined {
  const item = objectValue(value);
  if (!item) return undefined;

  for (const field of ["content", "title", "text", "value"] as const) {
    if (typeof item[field] === "string" && item[field].trim()) {
      return item[field].trim();
    }
  }

  return undefined;
}

function choicesFromInput(input: unknown) {
  const block = objectValue(input);
  if (!block || !Array.isArray(block.items)) return [];

  if (!["choice input", "picture choice input", "cards"].includes(String(block.type))) {
    return [];
  }

  return block.items
    .map(choiceLabel)
    .filter((label): label is string => Boolean(label));
}

export function mapTypebotOutput(output: ChatbotOutput): string[] {
  const messages = output.messages
    .map(bubbleText)
    .filter((message): message is string => Boolean(message));

  const choices = choicesFromInput(output.input);
  if (choices.length > 0) {
    messages.push(
      choices.map((choice, index) => `${index + 1} — ${choice}`).join("\n")
    );
  }

  return messages;
}

export function mapTypebotAnswer(message: string, input: unknown): string {
  const choices = choicesFromInput(input);
  const selection = Number(message.trim());

  if (!Number.isInteger(selection) || selection < 1 || selection > choices.length) {
    return message;
  }

  const block = objectValue(input);
  const item = Array.isArray(block?.items)
    ? objectValue(block.items[selection - 1])
    : undefined;

  return typeof item?.value === "string" && item.value.trim()
    ? item.value
    : choices[selection - 1] ?? message;
}
