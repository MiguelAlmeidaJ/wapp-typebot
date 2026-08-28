import type {
  SendTextInput
} from "./provider.js";

export function buildEvolutionTextPayload(
  input: SendTextInput
) {
  return {
    number:
      input.number,
    text:
      input.text,
    ...(input.quoted
      ? {
          /*
           * Evolution API 2.3.7 message.schema.ts accepts `quoted.key.id`
           * as the required quote locator. The provider can resolve the
           * original message from its own message store.
           */
          quoted: {
            key: {
              id:
                input
                  .quoted
                  .externalId
            }
          }
        }
      : {})
  };
}
