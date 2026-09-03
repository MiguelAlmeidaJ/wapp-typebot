import {
  readFile
} from "node:fs/promises";

const [
  ,
  ,
  envPath,
  key
] =
  process.argv;

if (
  !envPath ||
  !key
) {
  console.error(
    "Usage: node scripts/prod-env-value.mjs <env-file> <key>"
  );
  process.exit(
    2
  );
}

const source =
  await readFile(
    envPath,
    "utf8"
  );

let found =
  false;

for (
  const rawLine
  of source.split(
    /\r?\n/
  )
) {
  const line =
    rawLine.trim();

  if (
    !line ||
    line.startsWith(
      "#"
    )
  ) {
    continue;
  }

  const separator =
    line.indexOf(
      "="
    );

  if (
    separator <
      1
  ) {
    continue;
  }

  const candidate =
    line.slice(
      0,
      separator
    ).trim();

  if (
    candidate !==
    key
  ) {
    continue;
  }

  let value =
    line.slice(
      separator +
        1
    ).trim();

  if (
    (
      value.startsWith(
        '"'
      ) &&
      value.endsWith(
        '"'
      )
    ) ||
    (
      value.startsWith(
        "'"
      ) &&
      value.endsWith(
        "'"
      )
    )
  ) {
    value =
      value.slice(
        1,
        -1
      );
  }

  process.stdout.write(
    value
  );

  found =
    true;
  break;
}

if (
  !found
) {
  process.exit(
    3
  );
}
