import {
  timingSafeEqual
} from "node:crypto";

export function validMetricsAuthorization(
  expectedToken: string,
  authorization:
    | string
    | undefined
) {
  if (
    !expectedToken ||
    !authorization
      ?.startsWith(
        "Bearer "
      )
  ) {
    return false;
  }

  const candidate =
    authorization
      .slice(
        "Bearer ".length
      )
      .trim();

  const expected =
    Buffer.from(
      expectedToken
    );

  const received =
    Buffer.from(
      candidate
    );

  if (
    expected.length !==
    received.length
  ) {
    return false;
  }

  return timingSafeEqual(
    expected,
    received
  );
}
