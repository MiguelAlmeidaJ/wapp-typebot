# P1.26 Administrative audit trail

P1.26 adds append-only audit records for successful administrative mutations.

Audited actions include:

- team membership create/update;
- queue create/member replacement;
- SLA setting changes;
- tag create/update;
- quick-reply create/update;
- WhatsApp connection create/settings/connect request.

Each record stores company, actor membership, action, entity, request id,
IP/user-agent and sanitized before/after snapshots.

The audit deliberately excludes:

- passwords and password hashes;
- temporary passwords;
- refresh/access tokens;
- Evolution API keys/webhook secrets;
- QR payloads;
- full quick-reply bodies.

Read access:

`GET /api/v1/audit`

Permission:

`audit.read`

Only OWNER and ADMIN receive this capability in P1.26.

Audit writes occur after a successful business mutation. If the independent
audit write fails, the already completed business mutation is not rolled back;
the API logs the audit failure for operational investigation.
