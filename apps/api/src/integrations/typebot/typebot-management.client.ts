import { TypebotApiError } from "./typebot.types.js";

type FetchImplementation = typeof fetch;

interface TypebotWorkspace {
  id: string;
  name: string;
}

export interface ManagedTypebot {
  id: string;
  name: string;
  publicId: string | null;
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function requiredString(
  value: unknown,
  field: string,
  context: string
): string {
  if (typeof value === "string" && value) return value;

  throw new TypebotApiError(
    `O Typebot retornou ${context} sem o campo ${field}.`
  );
}

export class TypebotManagementClient {
  private readonly baseUrl: string;

  constructor(
    builderUrl: string,
    private readonly token: string,
    private readonly timeoutMs: number,
    private readonly fetchImplementation: FetchImplementation = fetch
  ) {
    this.baseUrl = `${builderUrl.replace(/\/+$/, "")}/api`;
  }

  private async request(
    method: "GET" | "POST" | "PATCH" | "DELETE",
    path: string,
    body?: unknown
  ): Promise<unknown> {
    let response: Response;

    try {
      response = await this.fetchImplementation(
        `${this.baseUrl}${path}`,
        {
          method,
          headers: {
            Authorization: `Bearer ${this.token}`,
            ...(body === undefined
              ? {}
              : { "Content-Type": "application/json" })
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
          signal: AbortSignal.timeout(this.timeoutMs)
        }
      );
    } catch (error) {
      throw new TypebotApiError(
        error instanceof Error && error.name === "TimeoutError"
          ? "O Typebot excedeu o tempo limite da requisição."
          : "Não foi possível acessar a API administrativa do Typebot."
      );
    }

    if (!response.ok) {
      const responseBody = (await response.text()).slice(0, 2_000);

      throw new TypebotApiError(
        `Typebot management request failed with status ${response.status}.`,
        response.status,
        responseBody
      );
    }

    if (response.status === 204) return undefined;

    const text = await response.text();
    if (!text) return undefined;

    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw new TypebotApiError(
        "O Typebot retornou JSON inválido na API administrativa."
      );
    }
  }

  async createWorkspace(name: string): Promise<TypebotWorkspace> {
    const response = objectValue(await this.request(
      "POST",
      "/v1/workspaces",
      { name }
    ));
    const workspace = objectValue(response?.workspace);

    return {
      id: requiredString(workspace?.id, "id", "um workspace"),
      name: requiredString(workspace?.name, "name", "um workspace")
    };
  }

  async deleteWorkspace(workspaceId: string): Promise<void> {
    await this.request(
      "DELETE",
      `/v1/workspaces/${encodeURIComponent(workspaceId)}`
    );
  }

  async createTypebot(input: {
    workspaceId: string;
    name: string;
    publicId: string;
  }): Promise<ManagedTypebot> {
    const response = objectValue(await this.request(
      "POST",
      "/v1/typebots",
      {
        workspaceId: input.workspaceId,
        typebot: {
          name: input.name,
          publicId: input.publicId
        }
      }
    ));
    const typebot = objectValue(response?.typebot);

    return {
      id: requiredString(typebot?.id, "id", "um typebot"),
      name: requiredString(typebot?.name, "name", "um typebot"),
      publicId:
        typeof typebot?.publicId === "string"
          ? typebot.publicId
          : null
    };
  }

  async updateTypebot(
    typebotId: string,
    patch: {
      name?: string;
      publicId?: string;
    }
  ): Promise<ManagedTypebot> {
    const response = objectValue(await this.request(
      "PATCH",
      `/v1/typebots/${encodeURIComponent(typebotId)}`,
      {
        typebot: patch,
        overwrite: true
      }
    ));
    const typebot = objectValue(response?.typebot);

    return {
      id: requiredString(typebot?.id, "id", "um typebot"),
      name: requiredString(typebot?.name, "name", "um typebot"),
      publicId:
        typeof typebot?.publicId === "string"
          ? typebot.publicId
          : null
    };
  }

  async publishTypebot(typebotId: string): Promise<void> {
    await this.request(
      "POST",
      `/v1/typebots/${encodeURIComponent(typebotId)}/publish`
    );
  }

  async deleteTypebot(typebotId: string): Promise<void> {
    await this.request(
      "DELETE",
      `/v1/typebots/${encodeURIComponent(typebotId)}`
    );
  }
}
