#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_DIR="apps/web/app"

echo "[P3.5.1c] Auditing every App Router page using useSearchParams..."

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: missing $APP_DIR"
  exit 1
fi

node <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const root =
  "apps/web/app";

function walk(dir) {
  const output = [];

  for (
    const entry
    of fs.readdirSync(
      dir,
      {
        withFileTypes:
          true
      }
    )
  ) {
    const full =
      path.join(
        dir,
        entry.name
      );

    if (
      entry.isDirectory()
    ) {
      output.push(
        ...walk(
          full
        )
      );
    } else if (
      entry.isFile() &&
      entry.name ===
        "page.tsx"
    ) {
      output.push(
        full
      );
    }
  }

  return output;
}

function alreadyWrapped(
  content
) {
  const hookIndex =
    content.indexOf(
      "useSearchParams()"
    );

  const defaultIndex =
    content.lastIndexOf(
      "export default function"
    );

  if (
    hookIndex <
      0 ||
    defaultIndex <
      0
  ) {
    return false;
  }

  /*
   * Our safe structure has the hook in an inner content component and the
   * default-exported route wrapper after it. Suspense must live in that
   * outer wrapper, not inside the hook-owning component.
   */
  if (
    defaultIndex >
      hookIndex
  ) {
    const tail =
      content.slice(
        defaultIndex
      );

    return (
      tail.includes(
        "<Suspense"
      ) &&
      /<Suspense[\s\S]*?>[\s\S]*?<[A-Za-z0-9_]+Content\s*\/>[\s\S]*?<\/Suspense>/
        .test(
          tail
        )
    );
  }

  return false;
}

const pages =
  walk(
    root
  );

const targets =
  pages.filter(
    file =>
      fs.readFileSync(
        file,
        "utf8"
      ).includes(
        "useSearchParams()"
      )
  );

if (
  targets.length ===
  0
) {
  console.log(
    "[P3.5.1c] No App Router pages use useSearchParams()."
  );

  process.exit(
    0
  );
}

console.log(
  `[P3.5.1c] Found ${targets.length} page(s) using useSearchParams():`
);

for (
  const file
  of targets
) {
  console.log(
    `  - ${file}`
  );
}

let changed =
  0;

for (
  const file
  of targets
) {
  let content =
    fs.readFileSync(
      file,
      "utf8"
    ).replace(
      /\r\n/g,
      "\n"
    );

  if (
    alreadyWrapped(
      content
    )
  ) {
    console.log(
      `[P3.5.1c] already safe: ${file}`
    );

    continue;
  }

  if (
    !content.startsWith(
      '"use client";'
    )
  ) {
    throw new Error(
      `${file}: useSearchParams page is not a client component. Inspect manually.`
    );
  }

  if (
    !content.includes(
      'import { Suspense } from "react";'
    )
  ) {
    const clientAnchor =
      '"use client";\n';

    if (
      !content.includes(
        clientAnchor
      )
    ) {
      throw new Error(
        `${file}: client directive anchor not found.`
      );
    }

    content =
      content.replace(
        clientAnchor,
        `${clientAnchor}
import { Suspense } from "react";
`
      );
  }

  const declarationPattern =
    /export\s+default\s+function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(\s*\)\s*\{/g;

  const declarations =
    Array.from(
      content.matchAll(
        declarationPattern
      )
    );

  if (
    declarations.length !==
    1
  ) {
    throw new Error(
      `${file}: expected exactly one zero-argument named default page function, found ${declarations.length}.`
    );
  }

  const pageName =
    declarations[0][1];

  if (
    !pageName
  ) {
    throw new Error(
      `${file}: could not resolve default page function name.`
    );
  }

  const contentName =
    `${pageName}Content`;

  if (
    content.includes(
      `function ${contentName}()`
    )
  ) {
    throw new Error(
      `${file}: ${contentName} already exists but page is not recognized as safely wrapped.`
    );
  }

  content =
    content.replace(
      declarationPattern,
      `function ${contentName}() {`
    );

  content =
    content.trimEnd() +
    `

export default function ${pageName}() {
  return (
    <Suspense
      fallback={
        <main className="dashboard-loading">
          Carregando…
        </main>
      }
    >
      <${contentName} />
    </Suspense>
  );
}
`;

  fs.writeFileSync(
    file,
    content
  );

  changed +=
    1;

  console.log(
    `[P3.5.1c] wrapped: ${file}`
  );
}

console.log(
  `[P3.5.1c] ${changed} page(s) changed.`
);
NODE

echo "[P3.5.1c] Verifying Suspense coverage..."

node <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const root =
  "apps/web/app";

function walk(dir) {
  const output = [];

  for (
    const entry
    of fs.readdirSync(
      dir,
      {
        withFileTypes:
          true
      }
    )
  ) {
    const full =
      path.join(
        dir,
        entry.name
      );

    if (
      entry.isDirectory()
    ) {
      output.push(
        ...walk(
          full
        )
      );
    } else if (
      entry.isFile() &&
      entry.name ===
        "page.tsx"
    ) {
      output.push(
        full
      );
    }
  }

  return output;
}

const unsafe =
  [];

const audited =
  [];

for (
  const file
  of walk(
    root
  )
) {
  const content =
    fs.readFileSync(
      file,
      "utf8"
    );

  const hookIndex =
    content.indexOf(
      "useSearchParams()"
    );

  if (
    hookIndex <
    0
  ) {
    continue;
  }

  audited.push(
    file
  );

  const defaultIndex =
    content.lastIndexOf(
      "export default function"
    );

  const tail =
    defaultIndex >=
      0
      ? content.slice(
          defaultIndex
        )
      : "";

  const safe =
    defaultIndex >
      hookIndex &&
    tail.includes(
      "<Suspense"
    ) &&
    /<Suspense[\s\S]*?>[\s\S]*?<[A-Za-z0-9_]+Content\s*\/>[\s\S]*?<\/Suspense>/
      .test(
        tail
      );

  if (
    !safe
  ) {
    unsafe.push(
      file
    );
  }
}

if (
  unsafe.length >
  0
) {
  throw new Error(
    `useSearchParams without verified outer Suspense:\n${unsafe
      .map(
        file =>
          `  - ${file}`
      )
      .join(
        "\n"
      )}`
  );
}

console.log(
  `[P3.5.1c] Suspense coverage PASS (${audited.length} page(s) audited).`
);
NODE

echo "[P3.5.1c] Web typecheck..."
pnpm --filter @wapp/web typecheck

echo "[P3.5.1c] Stabilization smoke..."
node scripts/p3-05-01-stabilization-smoke.mjs

echo "[P3.5.1c] Production build..."
pnpm build

echo
echo "[P3.5.1c] APP ROUTER BUILD PASS."
echo
echo "No Prisma migration is required."
echo "If this passes, commit + push the complete P3.5.1 stabilization set."
echo "Then verify the GitHub Quality Gate before P3.6."
