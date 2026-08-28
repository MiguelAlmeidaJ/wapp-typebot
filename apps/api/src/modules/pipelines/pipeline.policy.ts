export const PIPELINE_COLOR_KEYS = [
  "GRAY",
  "BLUE",
  "GREEN",
  "ORANGE",
  "PURPLE",
  "RED"
] as const;

export type PipelineColorKey =
  typeof PIPELINE_COLOR_KEYS[number];

export type PipelineStageOutcome =
  | "OPEN"
  | "WON"
  | "LOST";

export function normalizeStageNames(
  names: string[]
) {
  const seen =
    new Set<string>();

  const result:
    string[] =
    [];

  for (
    const raw
    of names
  ) {
    const name =
      raw
        .replace(
          /\s+/g,
          " "
        )
        .trim()
        .slice(
          0,
          120
        );

    if (
      !name
    ) {
      continue;
    }

    const key =
      name.toLocaleLowerCase(
        "pt-BR"
      );

    if (
      seen.has(
        key
      )
    ) {
      continue;
    }

    seen.add(
      key
    );

    result.push(
      name
    );
  }

  return result.slice(
    0,
    20
  );
}

export function stageMoveChanged(
  currentStageId:
    string
    | null
    | undefined,
  nextStageId:
    string
    | null
    | undefined
) {
  return (
    currentStageId ??
    null
  ) !==
    (
      nextStageId ??
      null
    );
}
