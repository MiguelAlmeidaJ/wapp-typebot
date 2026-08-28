# P2.1b Conversation identity + shell UX

P2.1b addresses three issues observed immediately after quoted replies.

## 1. Wrong contact names on fromMe messages

Evolution/Baileys `pushName` on a `fromMe` message can represent the sender
profile (the connected WhatsApp account), not the remote recipient.

Wapp previously used `pushName` for contact creation/update regardless of
direction. That could create several unrelated recipient conversations with
the connected account owner's name.

P2.1b rules:

- inbound direct message: `pushName` may update `whatsappName`;
- outbound/fromMe message: `pushName` never creates or renames the recipient;
- outbound contact fallback is phone number / remote JID;
- group behavior remains unchanged.

## 2. LID / phone-number identity

Evolution 2.3.7 exposes `remoteJidAlt`.

For a direct `@lid` message, when the alternate is an
`@s.whatsapp.net` JID, Wapp uses the phone-number JID as the canonical contact
key.

Groups are never replaced by an alternate participant identity.

## 3. Existing contaminated contacts

Dry run:

```bash
pnpm contacts:repair-identities
```

Apply only conservative repairs:

```bash
pnpm contacts:repair-identities:apply
```

A name is considered contaminated only when:

- the earliest stored message is OUTBOUND;
- that Evolution payload's pushName equals the current Contact.name;
- the contact later obtained a different `whatsappName`.

This is the signature of the previous fromMe naming bug.

The repair also upgrades a stored LID contact to its phone-number JID when
historical payloads provide `remoteJidAlt` and no other contact already owns
that canonical JID.

If a canonical contact already exists, the script reports a conflict and does
not merge contacts/tickets automatically.

## 4. Conversation home

The conversation page no longer auto-opens the first ticket.

With no selected ticket, the right pane shows:

- waiting count;
- open count;
- total active conversations;
- online team count;
- waiting conversations;
- conversations currently in service.

Opening a ticket is explicit.

The conversation header has a back-to-panel button.

## 5. Compact operation bar

Fila, atendente, transfer and the operational tools now use a compact wrapping
toolbar.

P2.1b does not change the canonical message layout:

- `.conversation-scroll` remains the message scroll;
- `.conversation-composer` remains outside that scroll and pinned.
