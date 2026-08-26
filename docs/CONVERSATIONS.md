# Conversations domain

P0.6 introduces the first operational Wapp domain.

```text
Evolution MESSAGES_UPSERT
          |
          v
       Contact
          |
          v
        Ticket
          |
          v
       Message
```

## Contact

A contact is unique by `companyId + remoteJid`.

The same contact can have multiple tickets over time.

## Ticket

Only one active ticket may exist for the same WhatsApp connection and contact.

This is guaranteed by the nullable unique `activeKey`:

```text
<whatsappConnectionId>:<contactId>
```

When the ticket is closed, `activeKey` becomes `NULL`. A later inbound message
can therefore create a new ticket.

## Message

Messages are deduplicated with:

```text
whatsappConnectionId + externalId
```

This protects the application from webhook retries.

P0.6 persists:

- text
- captions for common media messages
- media type
- MIME type when Evolution supplies it
- file name when Evolution supplies it
- raw webhook payload

Actual media download/storage is intentionally deferred to the next media
milestone.

## Realtime

The first inbox polls the API every 3 seconds. This is intentional for the
vertical slice.

After the domain is proven, polling will be replaced by realtime events without
changing the Contact/Ticket/Message model.
