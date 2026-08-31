import {
  createHash
} from "node:crypto";

export const MAX_IMPORT_ROWS =
  500;

export const MAX_IMPORT_COLUMNS =
  40;

export const MAX_IMPORT_CSV_CHARS =
  650_000;

export const MAX_EXPORT_ROWS =
  5_000;

export type ImportRowStatus =
  | "CREATE"
  | "UPDATE"
  | "CONFLICT"
  | "INVALID"
  | "SKIP";

export type ImportTarget =
  | "IGNORE"
  | "name"
  | "phone"
  | "email"
  | "notes"
  | `custom:${string}`
  | `pipeline:${string}`;

function firstRecord(
  csv:
    string
) {
  let record =
    "";
  let quoted =
    false;

  for (
    let index =
      0;
    index <
      csv.length;
    index +=
      1
  ) {
    const char =
      csv[index];

    if (
      char ===
      '"'
    ) {
      if (
        quoted &&
        csv[
          index +
            1
        ] ===
          '"'
      ) {
        record +=
          '""';
        index +=
          1;
        continue;
      }

      quoted =
        !quoted;
      record +=
        char;
      continue;
    }

    if (
      (
        char ===
          "\n" ||
        char ===
          "\r"
      ) &&
      !quoted
    ) {
      break;
    }

    record +=
      char;
  }

  return record;
}

function countDelimiter(
  record:
    string,
  delimiter:
    string
) {
  let quoted =
    false;
  let count =
    0;

  for (
    let index =
      0;
    index <
      record.length;
    index +=
      1
  ) {
    const char =
      record[index];

    if (
      char ===
      '"'
    ) {
      if (
        quoted &&
        record[
          index +
            1
        ] ===
          '"'
      ) {
        index +=
          1;
        continue;
      }

      quoted =
        !quoted;
      continue;
    }

    if (
      !quoted &&
      char ===
        delimiter
    ) {
      count +=
        1;
    }
  }

  return count;
}

export function detectCsvDelimiter(
  csv:
    string
) {
  const record =
    firstRecord(
      csv
    );

  const candidates =
    [
      ";",
      ",",
      "\t"
    ];

  let best =
    ";";

  let bestCount =
    -1;

  for (
    const candidate
    of candidates
  ) {
    const count =
      countDelimiter(
        record,
        candidate
      );

    if (
      count >
      bestCount
    ) {
      best =
        candidate;
      bestCount =
        count;
    }
  }

  return best;
}

export function parseCsv(
  raw:
    string
) {
  const csv =
    raw
      .replace(
        /^\uFEFF/,
        ""
      )
      .replace(
        /\r\n/g,
        "\n"
      )
      .replace(
        /\r/g,
        "\n"
      );

  if (
    !csv.trim()
  ) {
    throw new Error(
      "CSV_EMPTY"
    );
  }

  if (
    csv.length >
    MAX_IMPORT_CSV_CHARS
  ) {
    throw new Error(
      "CSV_TOO_LARGE"
    );
  }

  const delimiter =
    detectCsvDelimiter(
      csv
    );

  const records:
    string[][] =
    [];

  let row:
    string[] =
    [];

  let cell =
    "";

  let quoted =
    false;

  function pushCell() {
    if (
      cell.length >
      10_000
    ) {
      throw new Error(
        "CSV_CELL_TOO_LARGE"
      );
    }

    row.push(
      cell
    );

    cell =
      "";
  }

  function pushRow() {
    pushCell();

    const empty =
      row.every(
        value =>
          !value.trim()
      );

    if (
      !empty
    ) {
      if (
        row.length >
        MAX_IMPORT_COLUMNS
      ) {
        throw new Error(
          "CSV_TOO_MANY_COLUMNS"
        );
      }

      records.push(
        row
      );
    }

    row =
      [];
  }

  for (
    let index =
      0;
    index <
      csv.length;
    index +=
      1
  ) {
    const char =
      csv[index];

    if (
      quoted
    ) {
      if (
        char ===
        '"'
      ) {
        if (
          csv[
            index +
              1
          ] ===
          '"'
        ) {
          cell +=
            '"';

          index +=
            1;
        } else {
          quoted =
            false;
        }
      } else {
        cell +=
          char;
      }

      continue;
    }

    if (
      char ===
      '"'
    ) {
      quoted =
        true;
      continue;
    }

    if (
      char ===
      delimiter
    ) {
      pushCell();
      continue;
    }

    if (
      char ===
      "\n"
    ) {
      pushRow();
      continue;
    }

    cell +=
      char;
  }

  if (
    quoted
  ) {
    throw new Error(
      "CSV_UNCLOSED_QUOTE"
    );
  }

  if (
    cell.length >
      0 ||
    row.length >
      0
  ) {
    pushRow();
  }

  if (
    records.length <
    1
  ) {
    throw new Error(
      "CSV_EMPTY"
    );
  }

  const headers =
    records[
      0
    ]!
      .map(
        header =>
          header.trim()
      );

  if (
    headers.some(
      header =>
        !header
    )
  ) {
    throw new Error(
      "CSV_EMPTY_HEADER"
    );
  }

  const normalizedHeaders =
    headers.map(
      header =>
        header
          .trim()
          .toLocaleLowerCase(
            "pt-BR"
          )
    );

  if (
    new Set(
      normalizedHeaders
    ).size !==
    normalizedHeaders.length
  ) {
    throw new Error(
      "CSV_DUPLICATE_HEADER"
    );
  }

  const dataRows =
    records.slice(
      1
    );

  if (
    dataRows.length >
    MAX_IMPORT_ROWS
  ) {
    throw new Error(
      "CSV_TOO_MANY_ROWS"
    );
  }

  const rows =
    dataRows.map(
      (
        values,
        index
      ) => {
        const source:
          Record<
            string,
            string
          > =
          {};

        for (
          let column =
            0;
          column <
            headers.length;
          column +=
            1
        ) {
          source[
            headers[
              column
            ]!
          ] =
            values[
              column
            ] ??
            "";
        }

        return {
          rowNumber:
            index +
            2,
          source
        };
      }
    );

  return {
    delimiter,
    headers,
    rows
  };
}

export type NormalizedImportPhoneResult =
  | {
      phoneNumber: string;
      remoteJid: string;
    }
  | {
      error:
        | "INVALID_COUNTRY_CODE"
        | "PHONE_REQUIRED"
        | "INVALID_PHONE_LENGTH";
    };

export type NormalizedEmailResult =
  | {
      value: string | null;
    }
  | {
      error: "INVALID_EMAIL";
    };

export function normalizeImportPhone(input: {
  value:
    string;
  defaultCountryCode:
    string;
}): NormalizedImportPhoneResult {
  const raw =
    input.value.trim();

  const explicitInternational =
    raw.startsWith(
      "+"
    );

  let digits =
    raw.replace(
      /\D/g,
      ""
    );

  const countryCode =
    input.defaultCountryCode.replace(
      /\D/g,
      ""
    );

  if (
    !/^\d{1,3}$/.test(
      countryCode
    )
  ) {
    return {
      error:
        "INVALID_COUNTRY_CODE" as const
    };
  }

  if (
    !digits
  ) {
    return {
      error:
        "PHONE_REQUIRED" as const
    };
  }

  if (
    !explicitInternational &&
    (
      digits.length ===
        10 ||
      digits.length ===
        11
    )
  ) {
    digits =
      `${countryCode}${digits}`;
  }

  if (
    digits.length <
      11 ||
    digits.length >
      15
  ) {
    return {
      error:
        "INVALID_PHONE_LENGTH" as const
    };
  }

  return {
    phoneNumber:
      digits,
    remoteJid:
      `${digits}@s.whatsapp.net`
  };
}

export function normalizeEmail(
  value:
    string
): NormalizedEmailResult {
  const email =
    value
      .trim()
      .toLocaleLowerCase(
        "pt-BR"
      );

  if (
    !email
  ) {
    return {
      value:
        null
    };
  }

  if (
    email.length >
      190 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
      email
    )
  ) {
    return {
      error:
        "INVALID_EMAIL" as const
    };
  }

  return {
    value:
      email
  };
}

export function parseImportTarget(
  value:
    string
):
  ImportTarget
  | null {
  if (
    [
      "IGNORE",
      "name",
      "phone",
      "email",
      "notes"
    ].includes(
      value
    )
  ) {
    return value as
      ImportTarget;
  }

  if (
    /^custom:[0-9a-fA-F-]{36}$/.test(
      value
    ) ||
    /^pipeline:[0-9a-fA-F-]{36}$/.test(
      value
    )
  ) {
    return value as
      ImportTarget;
  }

  return null;
}

export function safeSpreadsheetCell(
  value:
    string
    | null
    | undefined
) {
  const text =
    value ??
    "";

  if (
    /^[\t\r\n]*[=+\-@]/.test(
      text
    )
  ) {
    return `'${text}`;
  }

  return text;
}

export function csvCell(
  value:
    string
    | null
    | undefined
) {
  const safe =
    safeSpreadsheetCell(
      value
    );

  if (
    /[;"\n\r]/.test(
      safe
    )
  ) {
    return `"${safe.replace(
      /"/g,
      '""'
    )}"`;
  }

  return safe;
}

export function planFingerprint(
  value:
    unknown
) {
  return createHash(
    "sha256"
  )
    .update(
      JSON.stringify(
        value
      )
    )
    .digest(
      "hex"
    );
}
