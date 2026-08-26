# WhatsApp provider architecture

Wapp does not call Baileys directly from the application domain.

```text
Wapp API
   |
   +-- WhatsAppProviderClient
           |
           +-- EvolutionWhatsAppClient
                    |
                    +-- Evolution API
                            |
                            +-- WHATSAPP-BAILEYS
```

This keeps tickets, contacts and messages independent from the WhatsApp engine.

## Local services

- Wapp API: http://localhost:4000
- Evolution API: http://localhost:8080
- Evolution PostgreSQL: internal Docker network only
- Evolution Redis: internal Docker network only

Evolution has its own PostgreSQL and Redis so its internal state is isolated from
Wapp's application database.

## Events subscribed in P0.5

- QRCODE_UPDATED
- CONNECTION_UPDATE
- MESSAGES_UPSERT

P0.5 only records connection state. Message ingestion starts in P0.6.

## Security

The Evolution global API key never reaches the browser.

Webhooks use a long secret URL path in the local P0.5 environment. In production
this must be combined with HTTPS and may be upgraded to signed/custom webhook
headers.
