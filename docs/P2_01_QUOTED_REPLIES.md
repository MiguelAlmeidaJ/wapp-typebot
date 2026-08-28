# P2.1 WhatsApp quoted replies

P2.1 closes the end-to-end quoted/reply flow.

## Inbound

Wapp already persisted `Message.quotedExternalId`.

P2.1 expands the Evolution parser so quoted `contextInfo.stanzaId` is also
recognized on image/audio/video/document/sticker/location/contact containers,
not only `extendedTextMessage`.

## History API

Ticket message pages now include:

```json
{
  "quotedExternalId": "...",
  "quotedMessage": {
    "id": "...",
    "externalId": "...",
    "direction": "INBOUND",
    "type": "TEXT",
    "body": "...",
    "mediaFileName": null,
    "timestamp": "..."
  }
}
```

The quoted preview is resolved company + ticket scoped.

If the referenced message is not present in Wapp's local history,
`quotedMessage` is `null`; the raw external id remains stored.

## Outbound text

`POST /api/v1/tickets/:id/messages`

accepts:

```json
{
  "text": "Resposta",
  "replyToMessageId": "<Wapp Message UUID>"
}
```

The API validates that the message belongs to the same company and ticket.

Evolution API 2.3.7 receives:

```json
{
  "number": "...",
  "text": "Resposta",
  "quoted": {
    "key": {
      "id": "<WhatsApp external message id>"
    }
  }
}
```

The resulting outbound Wapp message persists the original external id in
`quotedExternalId`.

## UI

Each loaded message has a reply action.

While composing, Wapp shows a compact "Respondendo a..." strip. Sending a text
includes `replyToMessageId`; cancelling only clears reply mode.

Messages that quote another message render a compact preview. Clicking the
preview jumps to the original. If the original is outside the loaded P1.21
window, Wapp loads the page around that message first.

## Scope

P2.1 intentionally quotes outbound TEXT messages only.

Attachment/media reply transport is left for a later P2 increment because
Evolution's multipart routes have a different transport contract. Existing
media and voice-note sending behavior is not changed.

## Migration

No Prisma migration is required. `quotedExternalId` already exists.
