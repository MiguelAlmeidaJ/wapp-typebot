import {
  readdir,
  rm,
  stat
} from "node:fs/promises";
import {
  join
} from "node:path";

const [
  ,
  ,
  directory,
  retentionDaysRaw,
  minKeepRaw,
  mode = "dry-run"
] =
  process.argv;

if (
  !directory ||
  !retentionDaysRaw ||
  !minKeepRaw
) {
  console.error(
    "Usage: prod-backup-prune.mjs <directory> <retention-days> <min-keep> [dry-run|apply]"
  );
  process.exit(
    2
  );
}

const retentionDays =
  Number(
    retentionDaysRaw
  );

const minKeep =
  Number(
    minKeepRaw
  );

if (
  !Number.isInteger(
    retentionDays
  ) ||
  !Number.isInteger(
    minKeep
  ) ||
  retentionDays <
    7 ||
  minKeep <
    1
) {
  throw new Error(
    "Invalid retention settings."
  );
}

if (
  ![
    "dry-run",
    "apply"
  ].includes(
    mode
  )
) {
  throw new Error(
    "Prune mode must be dry-run or apply."
  );
}

const entries =
  await readdir(
    directory,
    {
      withFileTypes:
        true
    }
  );

const backups =
  [];

for (
  const entry
  of entries
) {
  if (
    !entry.isFile() ||
    !/^wapp-db-\d{8}T\d{6}Z-[A-Za-z0-9._-]+\.wappbak$/.test(
      entry.name
    )
  ) {
    continue;
  }

  const path =
    join(
      directory,
      entry.name
    );

  const info =
    await stat(
      path
    );

  backups.push({
    name:
      entry.name,
    path,
    mtimeMs:
      info.mtimeMs
  });
}

backups.sort(
  (
    left,
    right
  ) =>
    right.mtimeMs -
    left.mtimeMs
);

const cutoff =
  Date.now() -
  retentionDays *
    24 *
    60 *
    60 *
    1000;

const candidates =
  backups
    .slice(
      minKeep
    )
    .filter(
      backup =>
        backup.mtimeMs <
        cutoff
    );

for (
  const backup
  of candidates
) {
  const manifest =
    backup.path.replace(
      /\.wappbak$/,
      ".manifest.json"
    );

  console.log(
    `[prod:backup:prune] ${mode === "apply" ? "DELETE" : "WOULD DELETE"} ${backup.path}`
  );

  if (
    mode ===
    "apply"
  ) {
    await rm(
      backup.path,
      {
        force:
          true
      }
    );

    await rm(
      manifest,
      {
        force:
          true
      }
    );
  }
}

console.log(
  `[prod:backup:prune] ${mode.toUpperCase()} PASS — ${backups.length} backup(s), ${candidates.length} candidate(s), minimum kept=${minKeep}, retention=${retentionDays}d.`
);
