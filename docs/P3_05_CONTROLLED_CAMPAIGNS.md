# P3.5 Controlled campaigns

P3.5 adds governed outbound campaigns over P3.4 saved segments.

## Eligibility

A contact is eligible only with explicit `OPTED_IN` campaign consent.

No consent row means UNKNOWN and is not eligible.

`OPTED_OUT` is never eligible.

Direct inbound commands `SAIR`, `PARAR`, `CANCELAR`, `REMOVER`,
`NAO QUERO RECEBER` and `NÃO QUERO RECEBER` automatically record opt-out.
The match is exact after normalization, avoiding accidental suppression from a
normal sentence that merely contains one of those words.

Every campaign message automatically appends:

`Para não receber mais mensagens, responda SAIR.`

The footer cannot be disabled.

## Dynamic segment and launch snapshot

Preview resolves the current P3.4 segment.

Start resolves it again and requires:

- exact current eligible count;
- literal confirmation `INICIAR CAMPANHA`.

Only after that is `CampaignRecipient` snapshot created.

Consent is checked again immediately before every provider send, so a contact
that opts out after campaign start is still suppressed.

## Initial safety limits

- direct contacts only;
- maximum segment audience: 500;
- explicit opt-in required;
- 1–10 messages/minute per campaign;
- global BullMQ limiter: 10 jobs/minute;
- explicit one-time window;
- maximum window: 24h.

The 500-contact limit is intentionally conservative for the first live rollout.

## Durable execution

Queue: `wapp-campaigns`.

Database recipient rows are the source of truth.

A one-minute sweep recovers pending recipients whose original enqueue did not
happen while Redis was unavailable.

Provider-send jobs use `attempts = 1`. Automatic provider retry is intentionally
disabled because a provider may accept a message even when local persistence
fails afterwards; retrying could duplicate the outbound message.

PROCESSING recipients older than 15 minutes become FAILED with an uncertain
state instead of being resent.

## Conversation integration

A successful campaign send uses the existing Evolution text path,
`Contact.remoteJid`, normal Ticket/Message persistence and
`deliveryStatus = PENDING`, so ordinary delivery/read webhooks continue the
message lifecycle.

Campaign messages appear in the same conversation history as manual and
scheduled outbound messages.

## RBAC

OWNER / ADMIN: read, prepare, start and cancel.

SUPERVISOR: read, prepare and cancel, but cannot start.

AGENT: read only.

Contact consent itself is an operational Contacts action.

## Personalization

Supported variables:

- `{{nome}}`
- `{{primeiro_nome}}`

No expression evaluation or arbitrary template code exists.

## Migration

P3.5 introduces:

- `ContactCampaignConsent`
- `Campaign`
- `CampaignRecipient`
- `CampaignEvent`
- related enums
