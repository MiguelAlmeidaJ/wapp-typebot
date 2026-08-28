export function notificationPreview(
  value:
    string
    | null
    | undefined,
  fallback =
    "Nova mensagem"
) {
  const normalized =
    value
      ?.replace(
        /\s+/g,
        " "
      )
      .trim();

  if (
    !normalized
  ) {
    return fallback;
  }

  return normalized.length >
    180
    ? `${normalized.slice(
        0,
        177
      )}...`
    : normalized;
}

export function inboundNotificationKey(
  ticketId: string,
  isNewTicket:
    boolean
) {
  return isNewTicket
    ? `new-ticket:${ticketId}`
    : `inbound:${ticketId}`;
}

export function uniqueMembershipIds(
  values:
    Array<
      string
      | null
      | undefined
    >
) {
  return [
    ...new Set(
      values.filter(
        (
          value
        ): value is string =>
          Boolean(
            value
          )
      )
    )
  ];
}
