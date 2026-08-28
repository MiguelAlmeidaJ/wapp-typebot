export function retentionCutoff(
  now: Date,
  retentionDays: number
) {
  return new Date(
    now.getTime() -
      retentionDays *
        24 *
        60 *
        60 *
        1_000
  );
}

export function staleMediaCutoff(
  now: Date,
  staleMinutes: number
) {
  return new Date(
    now.getTime() -
      staleMinutes *
        60 *
        1_000
  );
}
