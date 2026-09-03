import { access, cp } from "node:fs/promises";
import path from "node:path";

const webRoot = path.resolve(import.meta.dirname, "..");
const nextRoot = path.join(webRoot, ".next");

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

const standaloneCandidates = [
  path.join(nextRoot, "standalone", "apps", "web"),
  path.join(nextRoot, "standalone")
];

let standaloneRoot;

for (const candidate of standaloneCandidates) {
  if (await exists(path.join(candidate, "server.js"))) {
    standaloneRoot = candidate;
    break;
  }
}

if (!standaloneRoot) {
  throw new Error(
    "Next standalone server not found after build."
  );
}

await cp(
  path.join(nextRoot, "static"),
  path.join(standaloneRoot, ".next", "static"),
  { recursive: true, force: true }
);

const publicSource = path.join(webRoot, "public");

if (await exists(publicSource)) {
  await cp(
    publicSource,
    path.join(standaloneRoot, "public"),
    { recursive: true, force: true }
  );
}

console.log("Next standalone assets prepared.");
