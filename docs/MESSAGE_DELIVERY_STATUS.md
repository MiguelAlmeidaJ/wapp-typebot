# Message delivery status

P1.5 tracks the lifecycle of outbound WhatsApp messages.

```text
PENDING
   |
   v
SENT
   |
   v
DELIVERED
   |
   v
READ
   |
   +--> PLAYED (voice/audio)
```

A message can also enter `FAILED`.

## Evolution

Evolution initially returns sent messages as `PENDING`.

Later delivery/read changes are delivered through the `MESSAGES_UPDATE`
webhook.

For the Baileys integration Wapp accepts both numeric and textual status forms:

- 1 / PENDING
- 2 / SERVER_ACK / SENT
- 3 / DELIVERY_ACK / DELIVERED
- 4 / READ
- 5 / PLAYED
- 0 / ERROR / FAILED

Updates are monotonic: an out-of-order webhook cannot downgrade READ back to
DELIVERED.

## Existing instances

P1.5 adds `MESSAGES_UPDATE` to new-instance configuration.

Existing Evolution instances are upgraded when the Wapp connection is synced
or reconnected. `syncConnection` calls `/webhook/set/:instance` with the Wapp
event list.

## UI

Outbound bubbles show:

- circle: pending
- one check: sent
- double check: delivered
- green double check: read/played
- error indicator: failed

The API remains the source of truth; the UI does not infer delivery from a
successful HTTP send.
