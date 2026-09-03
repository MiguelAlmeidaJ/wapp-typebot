const EMAIL_PATTERN =
  /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizeBootstrapEmail(
  value:
    string
) {
  const normalized =
    value
      .trim()
      .toLowerCase();

  if (
    !EMAIL_PATTERN.test(
      normalized
    ) ||
    normalized.length >
      254
  ) {
    throw new Error(
      "Bootstrap OWNER email is invalid."
    );
  }

  return normalized;
}

export function normalizeRequiredLabel(
  value:
    string,
  label:
    string
) {
  const normalized =
    value
      .trim()
      .replace(
        /\s+/g,
        " "
      );

  if (
    normalized.length <
      2 ||
    normalized.length >
      120
  ) {
    throw new Error(
      `${label} must contain between 2 and 120 characters.`
    );
  }

  return normalized;
}

export function buildBootstrapCompanySlug(
  value:
    string
) {
  const slug =
    value
      .normalize(
        "NFKD"
      )
      .replace(
        /[\u0300-\u036f]/g,
        ""
      )
      .toLowerCase()
      .replace(
        /[^a-z0-9]+/g,
        "-"
      )
      .replace(
        /^-+|-+$/g,
        ""
      )
      .slice(
        0,
        72
      )
      .replace(
        /-+$/g,
        ""
      );

  return (
    slug ||
    "company"
  );
}

export function validateInitialOwnerPassword(
  password:
    string,
  email:
    string
) {
  if (
    password.length <
      14 ||
    password.length >
      256
  ) {
    throw new Error(
      "OWNER password must contain between 14 and 256 characters."
    );
  }

  const categories = [
    /[a-z]/.test(
      password
    ),
    /[A-Z]/.test(
      password
    ),
    /\d/.test(
      password
    ),
    /[^A-Za-z0-9]/.test(
      password
    )
  ].filter(
    Boolean
  ).length;

  if (
    categories <
      3
  ) {
    throw new Error(
      "OWNER password must use at least 3 of: lowercase, uppercase, number, symbol."
    );
  }

  const [
    localPart = ""
  ] =
    email.split(
      "@",
      1
    );

  if (
    localPart.length >=
      4 &&
    password
      .toLowerCase()
      .includes(
        localPart.toLowerCase()
      )
  ) {
    throw new Error(
      "OWNER password must not contain the email local-part."
    );
  }

  return password;
}
