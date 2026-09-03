import {
  execFileSync
} from "node:child_process";

const raw =
  execFileSync(
    "git",
    [
      "status",
      "--porcelain=v1",
      "--untracked-files=all"
    ],
    {
      encoding:
        "utf8"
    }
  );

const relevant =
  raw
    .split(
      /\r?\n/
    )
    .map(
      line =>
        line.trimEnd()
    )
    .filter(
      Boolean
    )
    .filter(
      line =>
        !/^\?\? .*\.patch$/i.test(
          line
        )
    );

if (
  relevant.length >
    0
) {
  console.error(
    "[RH6] release gate requires a clean Git working tree."
  );

  for (
    const line
    of relevant
  ) {
    console.error(
      line
    );
  }

  process.exit(
    1
  );
}

console.log(
  "[RH6] Git working tree PASS — clean (untracked .patch artifacts ignored)."
);
