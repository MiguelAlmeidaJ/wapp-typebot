# Wapp permission model

P0.9 moves authorization away from scattered `role === ...` checks.

## API capabilities

| Capability | OWNER | ADMIN | SUPERVISOR | AGENT |
| --- | --- | --- | --- | --- |
| admin.test | yes | yes | no | no |
| team.read | yes | yes | yes | yes |
| team.manage | yes | yes | no | no |
| queues.read | yes | yes | yes | yes |
| queues.manage | yes | yes | no | no |
| whatsapp.read | yes | yes | yes | yes |
| whatsapp.manage | yes | yes | no | no |
| whatsapp.test | yes | yes | yes | no |

Read permissions remain available to operational roles because ticket routing
and transfer flows need queue, team and connection metadata.

Management screens are separately protected in the Next application.

## UI capabilities

OWNER and ADMIN:
- Dashboard
- Conversations
- Queues management
- Connections management
- Team management
- Administrative RBAC test

SUPERVISOR and AGENT:
- Dashboard
- Conversations

The API is always the security boundary. Hiding a menu item is only UX.

## Ticket authorization

Ticket ownership/assignment rules remain inside the ticket domain service.
P0.9 intentionally does not replace those contextual checks with static role
permissions.
