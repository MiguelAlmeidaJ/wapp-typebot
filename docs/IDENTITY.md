# Identity and tenancy

The new Wapp identity model separates the user identity from company access.

```text
User
  |
  +-- CompanyMembership -- Company
              |
              +-- role
              +-- active/inactive
```

This lets one user participate in more than one company without duplicating
credentials.

## Roles

- OWNER
- ADMIN
- SUPERVISOR
- AGENT

Authorization always runs inside the company selected by the current session.

## Sessions

Access tokens are short-lived JWTs. Refresh tokens are opaque random values;
only their SHA-256 hashes are persisted. Refresh tokens rotate on every use.

Each session is linked to a user, company and membership. Revoking a session
immediately blocks protected routes.
