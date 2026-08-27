"use client";

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react";

import {
  ApiError,
  apiFetch,
  expectJson,
  parseApiError
} from "@/lib/api";
import type {
  AuthSession,
  CompanyRequiredDetails,
  LoginResponse,
  RefreshResponse
} from "@/lib/auth-types";
import type { RealtimeEvent } from "@/lib/realtime-types";

interface LoginInput {
  email: string;
  password: string;
  companySlug?: string;
}

interface AuthContextValue {
  session: AuthSession | null;
  loading: boolean;
  login(input: LoginInput): Promise<void>;
  logout(): Promise<void>;
  request<T>(path: string, init?: RequestInit): Promise<T>;
  requestRaw(path: string, init?: RequestInit): Promise<Response>;
  subscribe(
    path: string,
    onEvent: (event: RealtimeEvent) => void
  ): () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

async function refreshAccessToken(): Promise<string> {
  const response = await apiFetch("/api/v1/auth/refresh", {
    method: "POST"
  });

  const payload = await expectJson<RefreshResponse>(response);
  return payload.accessToken;
}

function wait(milliseconds: number) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const accessTokenRef = useRef<string | null>(null);
  const refreshPromiseRef = useRef<Promise<string> | null>(null);

  const [session, setSession] = useState<AuthSession | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshToken = useCallback(async () => {
    if (!refreshPromiseRef.current) {
      refreshPromiseRef.current = refreshAccessToken().finally(() => {
        refreshPromiseRef.current = null;
      });
    }

    const accessToken = await refreshPromiseRef.current;
    accessTokenRef.current = accessToken;
    return accessToken;
  }, []);

  const authenticatedFetch = useCallback(
    async (path: string, init: RequestInit = {}) => {
      let accessToken = accessTokenRef.current;

      if (!accessToken) {
        accessToken = await refreshToken();
      }

      const execute = (token: string) =>
        apiFetch(path, {
          ...init,
          headers: {
            ...init.headers,
            Authorization: `Bearer ${token}`
          }
        });

      let response = await execute(accessToken);

      if (response.status === 401) {
        accessToken = await refreshToken();
        response = await execute(accessToken);
      }

      return response;
    },
    [refreshToken]
  );

  const loadSession = useCallback(async () => {
    const response = await authenticatedFetch("/api/v1/auth/me");
    const payload = await expectJson<AuthSession>(response);
    setSession(payload);
    return payload;
  }, [authenticatedFetch]);

  useEffect(() => {
    let active = true;

    async function bootstrap() {
      try {
        await refreshToken();

        if (!active) {
          return;
        }

        await loadSession();
      } catch {
        accessTokenRef.current = null;

        if (active) {
          setSession(null);
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    void bootstrap();

    return () => {
      active = false;
    };
  }, [loadSession, refreshToken]);

  const login = useCallback(
    async (input: LoginInput) => {
      const response = await apiFetch("/api/v1/auth/login", {
        method: "POST",
        body: JSON.stringify(input)
      });

      const payload = await expectJson<LoginResponse>(response);

      accessTokenRef.current = payload.accessToken;
      setSession({
        user: payload.user,
        company: payload.company,
        role: payload.role
      });
    },
    []
  );

  const logout = useCallback(async () => {
    try {
      await apiFetch("/api/v1/auth/logout", {
        method: "POST"
      });
    } finally {
      accessTokenRef.current = null;
      setSession(null);
    }
  }, []);

  const request = useCallback(
    async <T,>(path: string, init: RequestInit = {}) => {
      const response = await authenticatedFetch(path, init);
      return expectJson<T>(response);
    },
    [authenticatedFetch]
  );

  const requestRaw = useCallback(
    async (path: string, init: RequestInit = {}) => {
      const response = await authenticatedFetch(
        path,
        init
      );

      if (!response.ok) {
        throw await parseApiError(response);
      }

      return response;
    },
    [authenticatedFetch]
  );

  const subscribe = useCallback(
    (
      path: string,
      onEvent: (event: RealtimeEvent) => void
    ) => {
      let cancelled = false;
      let controller: AbortController | null = null;

      async function connect() {
        while (!cancelled) {
          controller = new AbortController();

          try {
            const response = await authenticatedFetch(path, {
              headers: {
                Accept: "text/event-stream"
              },
              signal: controller.signal
            });

            if (!response.ok || !response.body) {
              throw new Error(
                `Realtime stream failed with ${response.status}.`
              );
            }

            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = "";

            while (!cancelled) {
              const { done, value } = await reader.read();

              if (done) {
                break;
              }

              buffer += decoder.decode(value, { stream: true });

              let boundary = buffer.indexOf("\n\n");

              while (boundary >= 0) {
                const block = buffer.slice(0, boundary);
                buffer = buffer.slice(boundary + 2);

                const data = block
                  .split("\n")
                  .filter(line => line.startsWith("data:"))
                  .map(line => line.slice(5).trim())
                  .join("\n");

                if (data) {
                  try {
                    onEvent(JSON.parse(data) as RealtimeEvent);
                  } catch {
                    // Ignore malformed frames and keep the stream alive.
                  }
                }

                boundary = buffer.indexOf("\n\n");
              }
            }
          } catch (error) {
            if (
              cancelled ||
              (error instanceof DOMException && error.name === "AbortError")
            ) {
              return;
            }
          }

          if (!cancelled) {
            await wait(1_500);
          }
        }
      }

      void connect();

      return () => {
        cancelled = true;
        controller?.abort();
      };
    },
    [authenticatedFetch]
  );

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      loading,
      login,
      logout,
      request,
      requestRaw,
      subscribe
    }),
    [session, loading, login, logout, request, requestRaw, subscribe]
  );

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error("useAuth must be used inside AuthProvider.");
  }

  return context;
}

export function getCompanyChoices(error: unknown) {
  if (!(error instanceof ApiError) || error.code !== "COMPANY_REQUIRED") {
    return [];
  }

  const details = error.details as CompanyRequiredDetails | undefined;
  return details?.companies ?? [];
}
