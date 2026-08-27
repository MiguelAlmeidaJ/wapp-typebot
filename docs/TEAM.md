# Team management

P0.8 manages access through `CompanyMembership`.

The global `User` identity remains separate from company access. This matters
because the same identity may participate in more than one company later.

Rules:

- OWNER can add ADMIN, SUPERVISOR and AGENT.
- ADMIN can add SUPERVISOR and AGENT.
- OWNER memberships are protected.
- A user cannot modify their own membership from this screen.
- Role/access changes revoke active sessions for that company membership.
- Deactivating a membership removes it from queues and returns its assigned
  active tickets to PENDING.
- If an email already exists globally, Wapp links the existing identity without
  changing its password.
- A temporary password is only required for a brand-new identity.
