import fs from "node:fs/promises";
import path from "node:path";

const args = process.argv.slice(2);
const apply = args.includes("--apply");

function value(name, fallback) {
  const index = args.indexOf(`--${name}`);
  if (index < 0) return fallback;
  const parsed = Number(args[index + 1]);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`--${name} must be an integer >= 0`);
  }
  return parsed;
}

const daily = value("daily", 7);
const weekly = value("weekly", 4);
const monthly = value("monthly", 6);
const root = path.resolve(process.env.WAPP_BACKUP_DIR ?? ".backups");

function parseDate(name) {
  const match = /^wapp-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/.exec(name);
  if (!match) return null;
  const [, y, m, d, hh, mm, ss] = match;
  const date = new Date(`${y}-${m}-${d}T${hh}:${mm}:${ss}Z`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function weekKey(date) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const start = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((d - start) / 86400000) + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

function keepBuckets(backups, keyFn, limit) {
  const keys = new Set();
  const kept = new Set();
  for (const backup of backups) {
    const key = keyFn(backup.date);
    if (keys.has(key)) continue;
    keys.add(key);
    if (kept.size < limit) kept.add(backup.name);
  }
  return kept;
}

let entries;
try {
  entries = await fs.readdir(root, { withFileTypes: true });
} catch (error) {
  if (error?.code === "ENOENT") {
    console.log("[backup:prune] No backup directory.");
    process.exit(0);
  }
  throw error;
}

const backups = entries
  .filter(entry => entry.isDirectory())
  .map(entry => ({ name: entry.name, date: parseDate(entry.name) }))
  .filter(item => item.date)
  .sort((a, b) => b.date - a.date);

if (backups.length === 0) {
  console.log("[backup:prune] No recognized snapshots.");
  process.exit(0);
}

const keep = new Set([backups[0].name]);
for (const name of keepBuckets(backups, d => d.toISOString().slice(0, 10), daily)) keep.add(name);
for (const name of keepBuckets(backups, weekKey, weekly)) keep.add(name);
for (const name of keepBuckets(backups, d => d.toISOString().slice(0, 7), monthly)) keep.add(name);

const remove = backups.filter(item => !keep.has(item.name));

console.log(`[backup:prune] snapshots=${backups.length} keep=${keep.size} remove=${remove.length}`);

for (const backup of remove) {
  console.log(`${apply ? "REMOVING" : "DRY-RUN"} ${backup.name}`);
  if (apply) {
    await fs.rm(path.join(root, backup.name), { recursive: true, force: false });
  }
}

if (!apply && remove.length > 0) {
  console.log("[backup:prune] Nothing removed. Add --apply to execute.");
}
