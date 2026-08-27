# API security hardening

P1.16 adds targeted production hardening without rate-limiting the WhatsApp
webhook path.

## Distributed authentication rate limits

Rate-limit state uses Redis when it is healthy and falls back to process-local
memory when Redis is unavailable.

Redis keys store SHA-256 hashes rather than raw email addresses or IP-derived
identifiers.

### Login

Two independent limits are enforced:

- 12 login attempts per IP in 15 minutes;
- 20 login attempts per normalized email + company slug in 15 minutes.

This gives protection against both single-IP brute force and broad credential
stuffing against one account.

### Refresh

Refresh is limited to:

- 60 requests per IP per minute.

Normal access-token refresh behavior is far below this threshold.

### Response

A blocked request returns HTTP `429` with:

- `Retry-After`;
- `RateLimit-Limit`;
- `RateLimit-Remaining`;
- `RateLimit-Reset`;
- error code `RATE_LIMITED`.

The API log contains the request id and rate-limit scope, but not the raw rate
limit key.

## WhatsApp webhooks

Evolution webhook routes are intentionally not placed behind the authentication
rate limits.

Inbound message bursts are legitimate workload and must not be dropped because
multiple customers send messages simultaneously.

Webhook authenticity continues to rely on the existing webhook secret and
message idempotency rules.

## Proxy awareness

`TRUST_PROXY=false` by default.

When Wapp is deployed behind a trusted reverse proxy/load balancer, set:

`TRUST_PROXY=true`

This allows Fastify `request.ip` to use the forwarded client address.

Do not enable `TRUST_PROXY=true` on an API that is directly reachable from
untrusted clients without a trusted proxy boundary.

## Request body size

`API_BODY_MAX_BYTES=1048576`

This is the default JSON/body limit for regular API requests.

Multipart media uploads continue to use the dedicated `MEDIA_MAX_BYTES` limit.

## Security headers

The API emits:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: no-referrer`
- restrictive `Permissions-Policy`
- restrictive document CSP

In production with secure cookies enabled it also emits HSTS.

## Redis outage

If Redis becomes unavailable, login protection degrades to a process-local
fallback rather than failing authentication completely.

In a multi-replica production deployment, Redis should be treated as required
infrastructure; P1.15 readiness already reports Redis failure.

## Migration

P1.16 requires no Prisma migration.
