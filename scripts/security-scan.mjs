import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = path.resolve(path.dirname(scriptPath), "..");
const ownRelativePath = "scripts/security-scan.mjs";
const maxFileBytes = 2 * 1024 * 1024;

const contentRules = [
  {
    id: "private-key",
    description: "material de chave privada versionado",
    pattern: /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/
  },
  {
    id: "aws-access-key",
    description: "possível AWS access key versionada",
    pattern: /\bAKIA[0-9A-Z]{16}\b/
  },
  {
    id: "github-token",
    description: "possível token GitHub versionado",
    pattern: /\bgh[pousr]_[A-Za-z0-9]{36,255}\b/
  },
  {
    id: "gitlab-token",
    description: "possível token GitLab versionado",
    pattern: /\bglpat-[A-Za-z0-9_-]{20,}\b/
  },
  {
    id: "slack-token",
    description: "possível token Slack versionado",
    pattern: /\bxox[baprs]-[A-Za-z0-9-]{20,}\b/
  },
  {
    id: "openai-api-key",
    description: "possível chave OpenAI versionada",
    pattern: /\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b/
  },
  {
    id: "google-api-key",
    description: "possível Google API key versionada",
    pattern: /\bAIza[0-9A-Za-z_-]{35}\b/
  },
  {
    id: "stripe-live-key",
    description: "possível chave Stripe live versionada",
    pattern: /\bsk_live_[0-9A-Za-z]{16,}\b/
  },
  {
    id: "hardcoded-bearer",
    description: "possível Bearer token hardcoded",
    pattern: /Authorization\s*[:=]\s*["'`]Bearer\s+[A-Za-z0-9._~+/=-]{16,}["'`]/i
  },
  {
    id: "disabled-tls-verification",
    description: "verificação TLS desativada",
    pattern: /NODE_TLS_REJECT_UNAUTHORIZED\s*[:=]\s*["']?0|rejectUnauthorized\s*:\s*false/
  },
  {
    id: "public-secret-variable",
    description: "segredo exposto por variável NEXT_PUBLIC",
    pattern: /\bNEXT_PUBLIC_[A-Z0-9_]*(?:SECRET|PASSWORD|PRIVATE|TOKEN|API_KEY)\b/
  },
  {
    id: "privileged-container",
    description: "container configurado em modo privilegiado",
    pattern: /^\s*privileged\s*:\s*true\s*(?:#.*)?$/im
  },
  {
    id: "docker-socket",
    description: "socket Docker montado em container",
    pattern: /\/var\/run\/docker\.sock/
  },
  {
    id: "host-network",
    description: "container usando a rede do host",
    pattern: /^\s*network_mode\s*:\s*["']?host["']?\s*(?:#.*)?$/im
  }
];

const frontendServerSecrets = [
  "TYPEBOT_API_TOKEN",
  "TYPEBOT_WEBHOOK_SECRET",
  "EVOLUTION_API_KEY",
  "EVOLUTION_WEBHOOK_SECRET",
  "JWT_SECRET",
  "S3_SECRET_ACCESS_KEY"
];

function repositoryFiles() {
  const output = execFileSync(
    "git",
    ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    {
      cwd: projectRoot,
      encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024
    }
  );

  return output.split("\0").filter(Boolean);
}

function isEnvironmentFile(relativePath) {
  const name = path.posix.basename(relativePath);
  return name === ".env" || (
    name.startsWith(".env.") &&
    !name.endsWith(".example")
  );
}

function lineNumber(content, index) {
  return content.slice(0, index).split("\n").length;
}

function addMatch(findings, relativePath, content, rule) {
  const match = rule.pattern.exec(content);
  if (!match) return;

  findings.push({
    rule: rule.id,
    description: rule.description,
    path: relativePath,
    line: lineNumber(content, match.index)
  });
}

function assertIgnored(relativePath, findings) {
  try {
    execFileSync("git", ["check-ignore", "-q", relativePath], {
      cwd: projectRoot,
      stdio: "ignore"
    });
  } catch {
    findings.push({
      rule: "secret-file-ignore",
      description: `${relativePath} não está protegido pelo .gitignore`,
      path: ".gitignore",
      line: 1
    });
  }
}

const findings = [];
const files = repositoryFiles();

assertIgnored("apps/api/.env", findings);
assertIgnored("apps/web/.env.local", findings);
assertIgnored("infra/evolution/.env", findings);
assertIgnored("infra/production/.env.production", findings);

for (const platformPath of files) {
  const relativePath = platformPath.replaceAll("\\", "/");

  if (relativePath === ownRelativePath) continue;

  if (isEnvironmentFile(relativePath)) {
    findings.push({
      rule: "tracked-environment-file",
      description: "arquivo de ambiente potencialmente sensível versionado",
      path: relativePath,
      line: 1
    });
  }

  if (/\.(?:key|p12|pfx|jks)$/i.test(relativePath)) {
    findings.push({
      rule: "tracked-key-file",
      description: "arquivo de chave potencialmente sensível versionado",
      path: relativePath,
      line: 1
    });
  }

  const absolutePath = path.join(projectRoot, ...relativePath.split("/"));
  let stats;
  try {
    stats = await fs.stat(absolutePath);
  } catch {
    continue;
  }

  if (!stats.isFile() || stats.size > maxFileBytes) continue;

  const buffer = await fs.readFile(absolutePath);
  if (buffer.includes(0)) continue;
  const content = buffer.toString("utf8");

  for (const rule of contentRules) {
    addMatch(findings, relativePath, content, rule);
  }

  if (relativePath.startsWith("apps/web/")) {
    for (const secretName of frontendServerSecrets) {
      const index = content.indexOf(secretName);
      if (index < 0) continue;

      findings.push({
        rule: "frontend-server-secret",
        description: `${secretName} referenciado no bundle web`,
        path: relativePath,
        line: lineNumber(content, index)
      });
    }
  }
}

if (findings.length > 0) {
  console.error(`[security:scan] Falhou com ${findings.length} achado(s):`);
  for (const finding of findings) {
    console.error(
      `- ${finding.path}:${finding.line} [${finding.rule}] ${finding.description}`
    );
  }
  process.exit(1);
}

console.log(`[security:scan] OK — ${files.length} arquivo(s) verificados.`);
