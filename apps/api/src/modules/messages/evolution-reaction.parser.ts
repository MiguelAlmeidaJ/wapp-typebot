import {
  canonicalRemoteJid
} from "./contact-identity.js";

export interface ParsedEvolutionReaction {
  targetExternalId: string;
  emoji: string;
  fromMe: boolean;
  reactorKey: string;
  reactorJid?: string;
  rawPayload:
    Record<string, unknown>;
}

function record(
  value: unknown
):
  | Record<string, unknown>
  | undefined {
  return value &&
    typeof value ===
      "object" &&
    !Array.isArray(
      value
    )
    ? value as
        Record<
          string,
          unknown
        >
    : undefined;
}

function text(
  value: unknown
) {
  return typeof value ===
      "string" &&
    value.length > 0
    ? value
    : undefined;
}

function reactionText(
  value: unknown
) {
  return typeof value ===
    "string"
    ? value
    : undefined;
}

function actorJid(
  key:
    Record<string, unknown>,
  remoteJid: string
) {
  const participant =
    text(
      key.participant
    );

  if (participant) {
    return canonicalRemoteJid({
      remoteJid:
        participant,
      remoteJidAlt:
        text(
          key.participantAlt
        )
    });
  }

  return canonicalRemoteJid({
    remoteJid,
    remoteJidAlt:
      text(
        key.remoteJidAlt
      )
  });
}

export function parseEvolutionReaction(
  payload:
    Record<string, unknown>
):
  | ParsedEvolutionReaction
  | null {
  const data =
    record(
      payload.data
    );

  const key =
    record(
      data?.key
    );

  const message =
    record(
      data?.message
    );

  const reaction =
    record(
      message
        ?.reactionMessage
    );

  const targetKey =
    record(
      reaction?.key
    );

  const remoteJid =
    text(
      key?.remoteJid
    );

  const targetExternalId =
    text(
      targetKey?.id
    );

  const emoji =
    reactionText(
      reaction?.text
    );

  if (
    !key ||
    !remoteJid ||
    !targetExternalId ||
    emoji ===
      undefined
  ) {
    return null;
  }

  const fromMe =
    key.fromMe ===
    true;

  const reactorJid =
    fromMe
      ? undefined
      : actorJid(
          key,
          remoteJid
        );

  return {
    targetExternalId,
    emoji:
      emoji.trim(),
    fromMe,
    reactorKey:
      fromMe
        ? "SELF"
        : reactorJid ??
          remoteJid,
    reactorJid,
    rawPayload:
      payload
  };
}
