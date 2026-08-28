const baseUrl =
  (
    process.env
      .WAPP_SMOKE_API_URL ??
    "http://localhost:4000"
  )
    .replace(
      /\/+$/,
      ""
    );

async function getJson(
  pathname
) {
  const url =
    `${baseUrl}${pathname}`;

  const startedAt =
    performance.now();

  let response;

  try {
    response =
      await fetch(
        url,
        {
          headers: {
            accept:
              "application/json"
          }
        }
      );
  } catch (error) {
    throw new Error(
      `${pathname}: API indisponível (${error instanceof Error ? error.message : "connection error"})`
    );
  }

  const latencyMs =
    Math.max(
      0,
      Math.round(
        performance.now() -
        startedAt
      )
    );

  const text =
    await response.text();

  let body;

  try {
    body =
      text
        ? JSON.parse(
            text
          )
        : null;
  } catch {
    body =
      text;
  }

  if (!response.ok) {
    throw new Error(
      `${pathname}: HTTP ${response.status} ${JSON.stringify(body)}`
    );
  }

  return {
    body,
    latencyMs
  };
}

try {
  console.log(
    `[smoke] API ${baseUrl}`
  );

  const live =
    await getJson(
      "/health/live"
    );

  if (
    live.body?.status !==
    "ok"
  ) {
    throw new Error(
      `/health/live respondeu estado inesperado: ${JSON.stringify(live.body)}`
    );
  }

  console.log(
    `[smoke] live: OK (${live.latencyMs} ms)`
  );

  const ready =
    await getJson(
      "/health/ready"
    );

  if (
    ready.body?.ready !==
    true
  ) {
    throw new Error(
      `/health/ready não está ready=true: ${JSON.stringify(ready.body)}`
    );
  }

  console.log(
    `[smoke] ready: OK (${ready.latencyMs} ms)`
  );

  const health =
    await getJson(
      "/health"
    );

  if (
    ![
      "ok",
      "degraded"
    ].includes(
      health.body?.status
    )
  ) {
    throw new Error(
      `/health respondeu estado inesperado: ${JSON.stringify(health.body)}`
    );
  }

  console.log(
    `[smoke] health: ${health.body.status} (${health.latencyMs} ms)`
  );

  console.log(
    "[smoke] PASS"
  );
} catch (error) {
  console.error(
    "[smoke] FAIL:",
    error instanceof Error
      ? error.message
      : error
  );

  process.exitCode = 1;
}
