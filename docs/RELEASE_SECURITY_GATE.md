# P1.23 Release security gate

P1.23 blocks production/release work when active Wapp source contains common
credential artifacts.

## Why this milestone exists

A curl-generated `cookies.txt` was found tracked in the active repository and
contained a Wapp refresh cookie.

The current branch removes that file and `.gitignore` now blocks local cookie
jars from being committed again.

The credential value is not copied into documentation, logs or scanner output.

## Local scan

```bash
pnpm security:scan
```

The scanner checks tracked active Wapp files for:

- cookie jars;
- tracked runtime `.env` files;
- private-key files/content;
- common GitHub token formats;
- AWS access-key identifiers;
- OpenAI-style project keys;
- Wapp refresh-cookie artifacts.

`legacy/` is excluded from this first active-code gate because it is retained as
reference material and requires a separate history/security cleanup plan before
any legacy content is republished or deployed.

The scanner reports only file + rule. It never prints the detected secret.

## Quality gate

`pnpm verify` now starts with:

```bash
pnpm security:scan
```

GitHub Actions runs the same security scan before Prisma generation, tests,
typecheck and build.

## Session revocation

Deleting a leaked refresh token from the current branch does not invalidate a
session that already exists in MySQL.

After installing P1.23, explicitly revoke all current sessions once:

```bash
pnpm security:revoke-sessions
```

This sets `revokedAt` on all active `Session` rows. No users, memberships,
messages or business data are deleted.

All users must sign in again afterward.

## Git history

Removing a secret from the current branch does not erase old Git commits.

For an opaque refresh token, session revocation makes that token unusable. If a
long-lived provider credential, password or private key is ever discovered in
Git history, rotate/revoke it first.

History rewriting is a separate operation because it changes commit SHAs and
can disrupt branches, clones and pull requests. P1.23 does not rewrite history
automatically.

## Release rule

Before deployment candidates:

```bash
pnpm verify
```

Then, with the target environment running:

```bash
pnpm smoke
```

P1.24 may proceed to production container/deployment baseline only after this
gate is green.
