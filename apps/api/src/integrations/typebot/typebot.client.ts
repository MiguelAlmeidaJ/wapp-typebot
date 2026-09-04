import {
  type ChatbotOutput,
  type ChatbotProvider,
  type ChatbotStartInput,
  TypebotApiError
} from "./typebot.types.js";

type FetchImplementation = typeof fetch;

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function parseOutput(value: unknown): ChatbotOutput {
  const body = objectValue(value);

  if (!body || !Array.isArray(body.messages)) {
    throw new TypebotApiError(
      "O Typebot retornou uma resposta incompatível."
    );
  }

  return {
    externalSessionId:
      typeof body.sessionId === "string"
        ? body.sessionId
        : undefined,
    messages: body.messages,
    input: body.input,
    clientSideActions: Array.isArray(body.clientSideActions)
      ? body.clientSideActions
      : undefined,
    raw: body
  };
}

export class TypebotClient implements ChatbotProvider {
  private readonly baseUrl: string;

  constructor(
    baseUrl: string,
    private readonly token: string,
    private readonly timeoutMs: number,
    private readonly fetchImplementation: FetchImplementation = fetch
  ) {
    this.baseUrl = baseUrl.replace(/\/+$/, "");
  }

  private async request(path: string, body: unknown): Promise<ChatbotOutput> {
    let response: Response;

    try {
      response = await this.fetchImplementation(
        `${this.baseUrl}${path}`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${this.token}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(this.timeoutMs)
        }
      );
    } catch (error) {
      throw new TypebotApiError(
        error instanceof Error && error.name === "TimeoutError"
          ? "O Typebot excedeu o tempo limite da requisição."
          : "Não foi possível acessar a API do Typebot."
      );
    }

    if (!response.ok) {
      const responseBody = (await response.text()).slice(0, 2_000);

      throw new TypebotApiError(
        `Typebot request failed with status ${response.status}.`,
        response.status,
        responseBody
      );
    }

    try {
      return parseOutput(await response.json());
    } catch (error) {
      if (error instanceof TypebotApiError) throw error;

      throw new TypebotApiError(
        "O Typebot retornou JSON inválido."
      );
    }
  }

  async start(input: ChatbotStartInput): Promise<ChatbotOutput> {
    const output = await this.request(
      `/v1/typebots/${encodeURIComponent(input.externalId)}/startChat`,
      {
        ...(input.message
          ? {
              message: {
                type: "text",
                text: input.message
              }
            }
          : {}),
        prefilledVariables: input.variables,
        textBubbleContentFormat: "markdown"
      }
    );

    if (!output.externalSessionId) {
      throw new TypebotApiError(
        "O Typebot não retornou o sessionId ao iniciar a conversa."
      );
    }

    return output;
  }

  continue(
    externalSessionId: string,
    message: string
  ): Promise<ChatbotOutput> {
    return this.request(
      `/v1/sessions/${encodeURIComponent(externalSessionId)}/continueChat`,
      {
        message: {
          type: "text",
          text: message
        },
        textBubbleContentFormat: "markdown"
      }
    );
  }

  async end(_externalSessionId: string): Promise<void> {
    // Typebot has no public endpoint for explicitly terminating a session.
  }
}
