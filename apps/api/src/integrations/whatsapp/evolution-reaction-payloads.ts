import type {
  SendReactionInput
} from "./provider.js";

export function buildEvolutionReactionPayload(
  input: SendReactionInput
) {
  return {
    key: {
      id:
        input.key.id,
      remoteJid:
        input.key.remoteJid,
      fromMe:
        input.key.fromMe
    },
    reaction:
      input.reaction
  };
}
