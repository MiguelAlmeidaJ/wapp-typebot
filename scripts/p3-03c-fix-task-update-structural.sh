#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILE="apps/api/src/modules/tasks/task.routes.ts"

echo "[P3.3c] Structurally repairing updateTask payload..."

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE"
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");

const path =
  "apps/api/src/modules/tasks/task.routes.ts";

let content =
  fs.readFileSync(
    path,
    "utf8"
  ).replace(
    /\r\n/g,
    "\n"
  );

const callNeedle =
  "await updateTask({";

const firstCall =
  content.indexOf(
    callNeedle
  );

if (
  firstCall < 0
) {
  throw new Error(
    "updateTask call not found."
  );
}

if (
  content.indexOf(
    callNeedle,
    firstCall +
      callNeedle.length
  ) >=
    0
) {
  throw new Error(
    "More than one updateTask call found; refusing ambiguous edit."
  );
}

const objectStart =
  content.indexOf(
    "{",
    firstCall
  );

if (
  objectStart < 0
) {
  throw new Error(
    "updateTask object start not found."
  );
}

let depth =
  0;
let inString =
  false;
let quote =
  "";
let escape =
  false;
let templateDepth =
  0;
let objectEnd =
  -1;

for (
  let index =
    objectStart;
  index <
    content.length;
  index +=
    1
) {
  const char =
    content[index];

  if (
    inString
  ) {
    if (
      escape
    ) {
      escape =
        false;
      continue;
    }

    if (
      char ===
      "\\"
    ) {
      escape =
        true;
      continue;
    }

    if (
      quote ===
        "`"
    ) {
      if (
        char ===
          "$" &&
        content[index +
          1] ===
          "{"
      ) {
        templateDepth +=
          1;
        index +=
          1;
        continue;
      }

      if (
        char ===
          "}" &&
        templateDepth >
          0
      ) {
        templateDepth -=
          1;
        continue;
      }

      if (
        char ===
          "`" &&
        templateDepth ===
          0
      ) {
        inString =
          false;
      }

      continue;
    }

    if (
      char ===
      quote
    ) {
      inString =
        false;
    }

    continue;
  }

  if (
    char ===
      '"' ||
    char ===
      "'" ||
    char ===
      "`"
  ) {
    inString =
      true;
    quote =
      char;
    templateDepth =
      0;
    continue;
  }

  if (
    char ===
    "{"
  ) {
    depth +=
      1;
  } else if (
    char ===
    "}"
  ) {
    depth -=
      1;

    if (
      depth ===
        0
    ) {
      objectEnd =
        index;
      break;
    }
  }
}

if (
  objectEnd < 0
) {
  throw new Error(
    "updateTask object end not found."
  );
}

let callBlock =
  content.slice(
    objectStart,
    objectEnd +
      1
  );

const alreadyNormalized =
  callBlock.includes(
    "...taskChanges"
  ) &&
  !callBlock.includes(
    "...input"
  );

if (
  !alreadyNormalized
) {
  const spreadMatches =
    callBlock.match(
      /\.\.\.input\s*,/g
    ) ??
    [];

  if (
    spreadMatches.length !==
    1
  ) {
    throw new Error(
      `Expected exactly one ...input spread inside updateTask, found ${spreadMatches.length}.`
    );
  }

  callBlock =
    callBlock.replace(
      /\.\.\.input\s*,/,
      "...taskChanges,"
    );

  callBlock =
    callBlock.replaceAll(
      "input.dueAt",
      "dueAt"
    );

  callBlock =
    callBlock.replaceAll(
      "input.reminderAt",
      "reminderAt"
    );

  content =
    content.slice(
      0,
      objectStart
    ) +
    callBlock +
    content.slice(
      objectEnd +
        1
    );
}

const normalizedCallIndex =
  content.indexOf(
    callNeedle
  );

const taskDeclaration =
  content.lastIndexOf(
    "const task =",
    normalizedCallIndex
  );

if (
  taskDeclaration < 0
) {
  throw new Error(
    "const task declaration before updateTask not found."
  );
}

const lineStart =
  content.lastIndexOf(
    "\n",
    taskDeclaration
  ) +
  1;

const indent =
  content.slice(
    lineStart,
    taskDeclaration
  );

const nearby =
  content.slice(
    Math.max(
      0,
      lineStart -
        500
    ),
    lineStart
  );

if (
  !nearby.includes(
    "...taskChanges"
  ) &&
  !nearby.includes(
    "reminderAt,\n"
  )
) {
  const destructuring =
    `${indent}const {
${indent}  dueAt,
${indent}  reminderAt,
${indent}  ...taskChanges
${indent}} =
${indent}  input;

`;

  content =
    content.slice(
      0,
      lineStart
    ) +
    destructuring +
    content.slice(
      lineStart
    );
}

const finalCallIndex =
  content.indexOf(
    callNeedle
  );

const finalObjectStart =
  content.indexOf(
    "{",
    finalCallIndex
  );

const finalWindow =
  content.slice(
    Math.max(
      0,
      finalCallIndex -
        500
    ),
    Math.min(
      content.length,
      finalObjectStart +
        1200
    )
  );

if (
  finalWindow.includes(
    "...input,"
  )
) {
  throw new Error(
    "Raw ...input spread still exists near updateTask."
  );
}

if (
  !finalWindow.includes(
    "...taskChanges,"
  ) ||
  !finalWindow.includes(
    "const {"
  ) ||
  !finalWindow.includes(
    "dueAt,"
  ) ||
  !finalWindow.includes(
    "reminderAt,"
  )
) {
  throw new Error(
    "Normalized updateTask structure verification failed."
  );
}

fs.writeFileSync(
  path,
  content
);

console.log(
  alreadyNormalized
    ? "[P3.3c] updateTask payload was already normalized; structure verified."
    : "[P3.3c] Raw date strings removed from updateTask spread."
);
NODE

echo "[P3.3c] API typecheck..."
pnpm --filter @wapp/api typecheck

echo "[P3.3c] Unit tests..."
pnpm test

echo "[P3.3c] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo
echo "[P3.3c] P3.3 CODE VALIDATION PASS."
echo
echo "Migration is still NOT executed by this hotfix."
echo "Next:"
echo "  pnpm --filter @wapp/api db:migrate"
echo "  pnpm test:integration"
echo "  pnpm dev"
