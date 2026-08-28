export type ContactFieldTypeValue =
  | "TEXT"
  | "NUMBER"
  | "DATE"
  | "BOOLEAN"
  | "SELECT";

export function fieldKeyFromLabel(
  label: string
) {
  const normalized =
    label
      .normalize(
        "NFD"
      )
      .replace(
        /[\u0300-\u036f]/g,
        ""
      )
      .toLowerCase()
      .replace(
        /[^a-z0-9]+/g,
        "_"
      )
      .replace(
        /^_+|_+$/g,
        ""
      )
      .slice(
        0,
        40
      );

  return normalized ||
    "campo";
}

export function normalizeSelectOptions(
  options:
    string[]
    | undefined
) {
  return [
    ...new Set(
      (
        options ??
        []
      )
        .map(
          option =>
            option
              .trim()
              .slice(
                0,
                80
              )
        )
        .filter(
          Boolean
        )
    )
  ].slice(
    0,
    50
  );
}

export function validateContactFieldValue(input: {
  type:
    ContactFieldTypeValue;
  value:
    string;
  options?:
    string[];
}) {
  const value =
    input.value.trim();

  if (
    !value
  ) {
    return null;
  }

  switch (
    input.type
  ) {
    case "TEXT":
      return value.length <=
        2_000
        ? null
        : "TEXT_TOO_LONG";

    case "NUMBER":
      return Number.isFinite(
        Number(
          value
        )
      )
        ? null
        : "INVALID_NUMBER";

    case "DATE": {
      if (
        !/^\d{4}-\d{2}-\d{2}$/.test(
          value
        )
      ) {
        return "INVALID_DATE";
      }

      const date =
        new Date(
          `${value}T00:00:00.000Z`
        );

      return Number.isNaN(
        date.getTime()
      ) ||
        date
          .toISOString()
          .slice(
            0,
            10
          ) !==
          value
        ? "INVALID_DATE"
        : null;
    }

    case "BOOLEAN":
      return [
        "true",
        "false"
      ].includes(
        value
      )
        ? null
        : "INVALID_BOOLEAN";

    case "SELECT":
      return (
        input.options ??
        []
      ).includes(
        value
      )
        ? null
        : "INVALID_OPTION";
  }
}
