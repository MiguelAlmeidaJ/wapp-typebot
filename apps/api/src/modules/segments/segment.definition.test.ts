import assert from "node:assert/strict";
import { test } from "node:test";
import { lastSeenCutoff, operatorAllowedForField, segmentDefinitionSchema } from "./segment.definition.js";

test("empty all-contacts definition is rejected", () => {
  assert.equal(segmentDefinitionSchema.safeParse({ search: null }).success, false);
});

test("segment definitions normalize defaults", () => {
  const parsed = segmentDefinitionSchema.parse({ hasPhone: "YES" });
  assert.equal(parsed.hasPhone, "YES");
  assert.equal(parsed.hasEmail, "ANY");
  assert.deepEqual(parsed.customFields, []);
});

test("last seen cutoff is deterministic", () => {
  const now = new Date("2026-08-31T12:00:00.000Z");
  assert.equal(lastSeenCutoff("WITHIN_7D", now)?.toISOString(), "2026-08-24T12:00:00.000Z");
});

test("contains is text-only while empty works for all fields", () => {
  assert.equal(operatorAllowedForField("TEXT", "CONTAINS"), true);
  assert.equal(operatorAllowedForField("NUMBER", "CONTAINS"), false);
  assert.equal(operatorAllowedForField("SELECT", "EMPTY"), true);
});
