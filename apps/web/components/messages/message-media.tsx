"use client";

import {
  useEffect,
  useState
} from "react";

import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

type MessageType =
  | "IMAGE"
  | "AUDIO"
  | "VIDEO"
  | "DOCUMENT"
  | "STICKER"
  | "TEXT"
  | "LOCATION"
  | "CONTACT"
  | "UNKNOWN";

type MediaStatus =
  | "NONE"
  | "PENDING"
  | "READY"
  | "FAILED";

export function MessageMedia({
  messageId,
  type,
  status,
  fileName,
  mimeType
}: {
  messageId: string;
  type: MessageType;
  status: MediaStatus;
  fileName: string | null;
  mimeType: string | null;
}) {
  const {
    request,
    requestRaw
  } = useAuth();

  const [objectUrl, setObjectUrl] =
    useState<string | null>(null);
  const [error, setError] =
    useState("");
  const [retrying, setRetrying] =
    useState(false);

  useEffect(() => {
    if (status !== "READY") {
      setObjectUrl(null);
      return;
    }

    let active = true;
    let currentUrl: string | null = null;

    void requestRaw(
      `/api/v1/messages/${messageId}/media`
    )
      .then(response => response.blob())
      .then(blob => {
        if (!active) {
          return;
        }

        currentUrl =
          URL.createObjectURL(blob);

        setObjectUrl(currentUrl);
        setError("");
      })
      .catch(() => {
        if (active) {
          setError(
            "Não foi possível abrir a mídia."
          );
        }
      });

    return () => {
      active = false;

      if (currentUrl) {
        URL.revokeObjectURL(currentUrl);
      }
    };
  }, [
    messageId,
    requestRaw,
    status
  ]);

  async function retry() {
    setRetrying(true);
    setError("");

    try {
      await request(
        `/api/v1/messages/${messageId}/media/retry`,
        {
          method: "POST"
        }
      );
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Falha ao recuperar mídia."
      );
    } finally {
      setRetrying(false);
    }
  }

  if (
    ![
      "IMAGE",
      "AUDIO",
      "VIDEO",
      "DOCUMENT",
      "STICKER"
    ].includes(type)
  ) {
    return null;
  }

  if (status === "PENDING") {
    return (
      <div className="message-media-state">
        Processando mídia…
      </div>
    );
  }

  if (
    status === "FAILED" ||
    error
  ) {
    return (
      <div className="message-media-state message-media-state--error">
        <span>
          {error ||
            "Mídia indisponível."}
        </span>
        <button
          disabled={retrying}
          onClick={retry}
          type="button"
        >
          {retrying
            ? "Tentando…"
            : "Tentar novamente"}
        </button>
      </div>
    );
  }

  if (
    status !== "READY" ||
    !objectUrl
  ) {
    return null;
  }

  if (
    type === "IMAGE" ||
    type === "STICKER"
  ) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        alt={fileName ?? "Imagem recebida"}
        className={
          type === "STICKER"
            ? "message-media-image message-media-image--sticker"
            : "message-media-image"
        }
        src={objectUrl}
      />
    );
  }

  if (type === "AUDIO") {
    return (
      <audio
        className="message-media-audio"
        controls
        preload="metadata"
        src={objectUrl}
      />
    );
  }

  if (type === "VIDEO") {
    return (
      <video
        className="message-media-video"
        controls
        preload="metadata"
        src={objectUrl}
      />
    );
  }

  return (
    <a
      className="message-media-document"
      download={fileName ?? true}
      href={objectUrl}
    >
      <span>Documento</span>
      <strong>
        {fileName ??
          mimeType ??
          "Baixar arquivo"}
      </strong>
    </a>
  );
}
