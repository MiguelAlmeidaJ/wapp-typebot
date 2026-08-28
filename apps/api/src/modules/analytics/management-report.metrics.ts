export function average(
  values: number[]
) {
  if (
    values.length ===
    0
  ) {
    return null;
  }

  return Math.round(
    values.reduce(
      (
        sum,
        value
      ) =>
        sum +
        value,
      0
    ) /
      values.length
  );
}

export function percent(
  numerator: number,
  denominator: number
) {
  if (
    denominator ===
    0
  ) {
    return null;
  }

  return Math.round(
    (
      numerator /
      denominator
    ) *
      100
  );
}

export function percentChange(
  current: number,
  previous: number
) {
  if (
    previous ===
    0
  ) {
    return current ===
      0
      ? 0
      : null;
  }

  return Math.round(
    (
      (
        current -
        previous
      ) /
      previous
    ) *
      100
  );
}

export function elapsedMinutes(
  from: Date,
  to: Date
) {
  return Math.max(
    0,
    Math.floor(
      (
        to.getTime() -
        from.getTime()
      ) /
        60_000
    )
  );
}
