export const API_URL =
  process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") ??
  "http://localhost:4000";

export interface ApiErrorBody {
  error?: {
    code?: string;
    message?: string;
    details?: unknown;
  };
}

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code = "API_ERROR",
    public readonly details?: unknown
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function apiFetch(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  return fetch(`${API_URL}${path}`, {
    ...init,
    credentials: "include",
    headers: {
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers
    }
  });
}

export async function parseApiError(response: Response): Promise<ApiError> {
  let body: ApiErrorBody | undefined;

  try {
    body = (await response.json()) as ApiErrorBody;
  } catch {
    // Keep the fallback below when the API did not return JSON.
  }

  return new ApiError(
    body?.error?.message ?? `A API respondeu com status ${response.status}.`,
    response.status,
    body?.error?.code ?? "API_ERROR",
    body?.error?.details
  );
}

export async function expectJson<T>(response: Response): Promise<T> {
  if (!response.ok) {
    throw await parseApiError(response);
  }

  return (await response.json()) as T;
}
