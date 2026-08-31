import fs from "node:fs";

const schema = fs.readFileSync("apps/api/prisma/schema.prisma", "utf8");
const service = fs.readFileSync("apps/api/src/modules/segments/segment.service.ts", "utf8");
const dashboard = fs.readFileSync("apps/web/app/dashboard/page.tsx", "utf8");
const page = fs.readFileSync("apps/web/app/dashboard/segments/page.tsx", "utf8");
const permissions = fs.readFileSync("apps/api/src/security/permissions.ts", "utf8");

const checks = [
  [schema, "model ContactSegment {"],
  [schema, "definition            Json"],
  [service, "buildSegmentWhere"],
  [service, "isGroup: false"],
  [service, "customFieldValues"],
  [service, "pipelineStates"],
  [service, "crmTasks"],
  [dashboard, 'href: "/dashboard/segments"'],
  [permissions, '"segments.read"'],
  [permissions, '"segments.manage"'],
  [page, "A audiência é recalculada"]
];

for (const [source, marker] of checks) {
  if (!source.includes(marker)) throw new Error(`P3.4 marker missing: ${marker}`);
}

console.log("[P3.4] segment smoke PASS");
