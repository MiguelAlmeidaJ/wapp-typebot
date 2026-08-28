#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[P1.23] Installing release security gate..."

for required in \
  "package.json" \
  "apps/api/package.json" \
  ".gitignore"
do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required"
    exit 1
  fi
done

mkdir -p \
  apps/api/src/scripts \
  scripts \
  docs

# ---------------------------------------------------------------------------
# Remove known tracked auth cookie artifact from the active branch.
# ---------------------------------------------------------------------------

if git ls-files --error-unmatch cookies.txt >/dev/null 2>&1; then
  echo "[P1.23] Removing tracked cookies.txt..."
  git rm -f -- cookies.txt
else
  rm -f cookies.txt
fi

if ! grep -q '^cookies\.txt$' .gitignore; then
  cat >> .gitignore <<'EOF'

# --- WAPP P1.23 / LOCAL AUTH ARTIFACTS ---
cookies.txt
*.cookies.txt
*.cookiejar
# --- /WAPP P1.23 ---
EOF
fi

# ---------------------------------------------------------------------------
# Tracked-file secret scan for active Wapp source.
# ---------------------------------------------------------------------------

cat > scripts/security-scan.mjs <<'EOF'
import {
  readFile
} from "node:fs/promises";
import {
  spawnSync
} from "node:child_process";

function trackedFiles() {
  const result =
    spawnSync(
      "git",
      [
        "ls-files",
        "-z"
      ],
      {
        encoding:
          "utf8"
      }
    );

  if (
    result.status !==
    0
  ) {
    throw new Error(
      "git ls-files failed."
    );
  }

  return result.stdout
    .split("\0")
    .filter(Boolean);
}

function activeFile(
  file
) {
  return !(
    file.startsWith(
      "legacy/"
    ) ||
    file.startsWith(
      ".backups/"
    ) ||
    file.endsWith(
      ".patch"
    )
  );
}

const forbiddenNames = [
  /(^|\/)cookies?\.txt$/i,
  /(^|\/).*\.cookiejar$/i,
  /(^|\/)id_rsa$/i,
  /(^|\/)id_ed25519$/i,
  /(^|\/).*\.p12$/i,
  /(^|\/).*\.pfx$/i,
  /(^|\/)\.env$/i,
  /(^|\/)\.env\.local$/i,
  /(^|\/)\.env\.production$/i
];

const forbiddenContent = [
  {
    name:
      "private key",
    pattern:
      /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/
  },
  {
    name:
      "GitHub personal access token",
    pattern:
      /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b/
  },
  {
    name:
      "GitHub fine-grained token",
    pattern:
      /\bgithub_pat_[A-Za-z0-9_]{30,}\b/
  },
  {
    name:
      "AWS access key",
    pattern:
      /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/
  },
  {
    name:
      "OpenAI-style project key",
    pattern:
      /\bsk-proj-[A-Za-z0-9_-]{20,}\b/
  },
  {
    name:
      "Wapp refresh cookie",
    pattern:
      /\bwapp_refresh\s+[^\s]{20,}/
  }
];

try {
  const files =
    trackedFiles()
      .filter(
        activeFile
      );

  const failures = [];

  for (
    const file
    of files
  ) {
    for (
      const rule
      of forbiddenNames
    ) {
      if (
        rule.test(
          file
        )
      ) {
        failures.push(
          `${file}: forbidden tracked secret/artifact filename`
        );
      }
    }

    let content;

    try {
      content =
        await readFile(
          file,
          "utf8"
        );
    } catch {
      continue;
    }

    for (
      const rule
      of forbiddenContent
    ) {
      if (
        rule.pattern.test(
          content
        )
      ) {
        failures.push(
          `${file}: possible ${rule.name}`
        );
      }
    }
  }

  if (
    failures.length >
    0
  ) {
    console.error(
      "[security:scan] FAIL"
    );

    for (
      const failure
      of failures
    ) {
      console.error(
        `  - ${failure}`
      );
    }

    console.error(
      "[security:scan] Values are intentionally not printed."
    );

    process.exit(1);
  }

  console.log(
    `[security:scan] PASS — ${files.length} tracked active files checked.`
  );
} catch (error) {
  console.error(
    "[security:scan] ERROR:",
    error instanceof Error
      ? error.message
      : error
  );

  process.exitCode = 1;
}
EOF

# ---------------------------------------------------------------------------
# Explicit session revocation command.
# ---------------------------------------------------------------------------

cat > apps/api/src/scripts/revoke-all-sessions.ts <<'EOF'
import { prisma } from "../lib/database.js";

try {
  const now =
    new Date();

  const result =
    await prisma.session.updateMany({
      where: {
        revokedAt: null
      },
      data: {
        revokedAt:
          now
      }
    });

  console.log(
    `[security] Revoked ${result.count} active session(s).`
  );

  console.log(
    "[security] All users must sign in again."
  );
} catch (error) {
  console.error(
    "[security] Session revocation failed:",
    error instanceof Error
      ? error.message
      : error
  );

  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
EOF

# ---------------------------------------------------------------------------
# Package commands.
# ---------------------------------------------------------------------------

node <<'NODE'
const fs = require("node:fs");

const apiPath =
  "apps/api/package.json";

const api =
  JSON.parse(
    fs.readFileSync(
      apiPath,
      "utf8"
    )
  );

api.scripts ??= {};

api.scripts["security:revoke-sessions"] =
  "tsx src/scripts/revoke-all-sessions.ts";

fs.writeFileSync(
  apiPath,
  `${JSON.stringify(
    api,
    null,
    2
  )}\n`
);

const rootPath =
  "package.json";

const root =
  JSON.parse(
    fs.readFileSync(
      rootPath,
      "utf8"
    )
  );

root.scripts ??= {};

root.scripts["security:scan"] =
  "node scripts/security-scan.mjs";

root.scripts["security:revoke-sessions"] =
  "pnpm --filter @wapp/api security:revoke-sessions";

const currentVerify =
  root.scripts.verify;

if (
  typeof currentVerify ===
    "string" &&
  !currentVerify.startsWith(
    "pnpm security:scan &&"
  )
) {
  root.scripts.verify =
    `pnpm security:scan && ${currentVerify}`;
}

fs.writeFileSync(
  rootPath,
  `${JSON.stringify(
    root,
    null,
    2
  )}\n`
);

console.log(
  "Security package commands registered."
);
NODE

# ---------------------------------------------------------------------------
# CI quality gate integration.
# ---------------------------------------------------------------------------

if [[ -f ".github/workflows/quality-gate.yml" ]] &&
   ! grep -q "Security scan" .github/workflows/quality-gate.yml
then
  node <<'NODE'
const fs = require("node:fs");

const path =
  ".github/workflows/quality-gate.yml";

let content =
  fs.readFileSync(
    path,
    "utf8"
  );

const anchor = `      - name: Generate Prisma client
        run: pnpm db:generate`;

if (!content.includes(anchor)) {
  throw new Error(
    "Quality Gate Prisma step anchor not found."
  );
}

content =
  content.replace(
    anchor,
    `      - name: Security scan
        run: pnpm security:scan

${anchor}`
  );

fs.writeFileSync(
  path,
  content
);

console.log(
  "GitHub Actions security scan installed."
);
NODE
fi

# ---------------------------------------------------------------------------
# Documentation.
# ---------------------------------------------------------------------------

cat > docs/RELEASE_SECURITY_GATE.md <<'EOF'
# P1.23 Release security gate

P1.23 blocks production/release work when active Wapp source contains common
credential artifacts.

## Why this milestone exists

A curl-generated `cookies.txt` was found tracked in the active repository and
contained a Wapp refresh cookie.

The current branch removes that file and `.gitignore` now blocks local cookie
jars from being committed again.

The credential value is not copied into documentation, logs or scanner output.

## Local scan

```bash
pnpm security:scan
```

The scanner checks tracked active Wapp files for:

- cookie jars;
- tracked runtime `.env` files;
- private-key files/content;
- common GitHub token formats;
- AWS access-key identifiers;
- OpenAI-style project keys;
- Wapp refresh-cookie artifacts.

`legacy/` is excluded from this first active-code gate because it is retained as
reference material and requires a separate history/security cleanup plan before
any legacy content is republished or deployed.

The scanner reports only file + rule. It never prints the detected secret.

## Quality gate

`pnpm verify` now starts with:

```bash
pnpm security:scan
```

GitHub Actions runs the same security scan before Prisma generation, tests,
typecheck and build.

## Session revocation

Deleting a leaked refresh token from the current branch does not invalidate a
session that already exists in MySQL.

After installing P1.23, explicitly revoke all current sessions once:

```bash
pnpm security:revoke-sessions
```

This sets `revokedAt` on all active `Session` rows. No users, memberships,
messages or business data are deleted.

All users must sign in again afterward.

## Git history

Removing a secret from the current branch does not erase old Git commits.

For an opaque refresh token, session revocation makes that token unusable. If a
long-lived provider credential, password or private key is ever discovered in
Git history, rotate/revoke it first.

History rewriting is a separate operation because it changes commit SHAs and
can disrupt branches, clones and pull requests. P1.23 does not rewrite history
automatically.

## Release rule

Before deployment candidates:

```bash
pnpm verify
```

Then, with the target environment running:

```bash
pnpm smoke
```

P1.24 may proceed to production container/deployment baseline only after this
gate is green.
EOF

# ---------------------------------------------------------------------------
# Validation.
# ---------------------------------------------------------------------------

echo "[P1.23] Node syntax..."
node --check scripts/security-scan.mjs

echo "[P1.23] Security scan..."
pnpm security:scan

echo "[P1.23] Typechecking API..."
pnpm --filter @wapp/api typecheck

echo "[P1.23] Typechecking web..."
pnpm --filter @wapp/web typecheck

echo
echo "[P1.23] Release security gate installed."
echo
echo "IMPORTANT — run once against your current database:"
echo "  pnpm security:revoke-sessions"
echo
echo "Then sign in again and run:"
echo "  pnpm verify"
