# P2.2 Native WhatsApp message reactions

P2.2 stores reactions separately from chat messages.

A reaction does not change ticket unread count, SLA clocks or last-message
preview.

## Evolution 2.3.7

Outbound endpoint:

`POST /message/sendReaction/:instance`

Payload:

```json
{
  "key": {
    "id": "<target external id>",
    "remoteJid": "<conversation jid>",
    "fromMe": false
  },
  "reaction": "👍"
}
```

An empty reaction removes the connected account's current reaction.

Inbound `MESSAGES_UPSERT` events containing `message.reactionMessage` are
handled before ordinary message ingestion.

## Persistence

`MessageReaction` keeps one current reaction for each message/reactor key.

Changing emoji replaces the existing reaction. Removing it deletes that
message/reactor state.

## Realtime

`message.reaction.updated` refreshes only the reaction state of the affected
message and preserves the P1.21 paginated message window.

## UI

The picker contains:

`👍 ❤️ 😂 😮 😢 🙏`

Click the active reaction again to remove it.
