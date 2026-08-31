"use client";

import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/components/auth-provider";
import { ApiError } from "@/lib/api";

interface Payload {
  status: "UNKNOWN" | "OPTED_IN" | "OPTED_OUT";
  consent: {
    status: "OPTED_IN" | "OPTED_OUT";
    source: "MANUAL" | "INBOUND_KEYWORD";
    note: string | null;
  } | null;
}

export function ContactCampaignConsent({ contactId }: { contactId: string }) {
  const { request, subscribe } = useAuth();
  const [payload, setPayload] = useState<Payload | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    setPayload(
      await request<Payload>(
        `/api/v1/contacts/${contactId}/campaign-consent`
      )
    );
  }, [contactId, request]);

  useEffect(() => {
    void load().catch(() => {
      setError("Não foi possível carregar o consentimento.");
    });
  }, [load]);

  useEffect(
    () =>
      subscribe("/api/v1/realtime/events", event => {
        if (
          event.type === "campaign.consent.updated" &&
          event.contactId === contactId
        ) {
          void load();
        }
      }),
    [contactId, load, subscribe]
  );

  async function setStatus(status: "OPTED_IN" | "OPTED_OUT") {
    setBusy(true);
    setError("");
    try {
      await request(
        `/api/v1/contacts/${contactId}/campaign-consent`,
        {
          method: "PUT",
          body: JSON.stringify({
            status,
            note:
              status === "OPTED_IN"
                ? "Consentimento registrado manualmente no Wapp."
                : "Contato marcado para não receber campanhas."
          })
        }
      );
      await load();
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível atualizar o consentimento."
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="contact-campaign-consent">
      <div>
        <span className="eyebrow">Campanhas</span>
        <strong>Consentimento</strong>
        <small>
          Sem autorização explícita, o contato fica fora de campanhas.
        </small>
      </div>

      <span className={`contact-consent-badge contact-consent-badge--${payload?.status ?? "UNKNOWN"}`}>
        {payload?.status === "OPTED_IN"
          ? "Autorizado"
          : payload?.status === "OPTED_OUT"
            ? "Opt-out"
            : "Não informado"}
      </span>

      <div className="contact-campaign-consent__actions">
        <button
          disabled={busy}
          onClick={() => void setStatus("OPTED_IN")}
          type="button"
        >
          Registrar autorização
        </button>
        <button
          disabled={busy}
          onClick={() => void setStatus("OPTED_OUT")}
          type="button"
        >
          Não receber
        </button>
      </div>

      {error && <small className="contact-consent-error">{error}</small>}
    </section>
  );
}
