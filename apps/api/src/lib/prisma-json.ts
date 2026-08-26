import type { Prisma } from "../generated/prisma/client.js";

/**
 * Prisma's JSON input type is intentionally stricter than `unknown`.
 *
 * HTTP webhook payloads are already JSON-compatible at runtime, but TypeScript
 * cannot infer that from Record<string, unknown>. Serializing once also removes
 * any accidental `undefined` values before persistence.
 */
export function toPrismaJson(
  value: unknown
): Prisma.InputJsonValue | undefined {
  if (value === undefined) {
    return undefined;
  }

  const serialized = JSON.stringify(value);

  if (serialized === undefined) {
    return undefined;
  }

  return JSON.parse(serialized) as Prisma.InputJsonValue;
}
