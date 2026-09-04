export interface ChatbotStartInput {
  externalId: string;
  message?: string;
  variables?: Record<string, string>;
}

export interface ChatbotOutput {
  externalSessionId?: string;
  messages: unknown[];
  input?: unknown;
  clientSideActions?: unknown[];
  raw: Record<string, unknown>;
}

export interface ChatbotProvider {
  start(input: ChatbotStartInput): Promise<ChatbotOutput>;

  continue(
    externalSessionId: string,
    message: string
  ): Promise<ChatbotOutput>;

  end(externalSessionId: string): Promise<void>;
}

export class TypebotApiError extends Error {
  constructor(
    message: string,
    readonly status?: number,
    readonly responseBody?: string
  ) {
    super(message);
    this.name = "TypebotApiError";
  }
}
