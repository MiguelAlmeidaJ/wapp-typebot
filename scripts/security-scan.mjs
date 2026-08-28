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
