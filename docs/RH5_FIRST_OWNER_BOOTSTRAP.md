# RH5 — First OWNER bootstrap

RH5 provides a dedicated production-only first-OWNER workflow.

It is intentionally separate from Prisma development seeding.

## Security properties

The bootstrap:

- works only when the identity database is empty;
- derives the required Company slug deterministically from the company name;
- refuses to run if any OWNER already exists;
- refuses to guess how to merge pre-existing users, companies or memberships;
- serializes concurrent attempts with a MySQL named lock;
- creates Company + User + OWNER membership in one transaction;
- generates an unguessable bootstrap password in memory;
- hashes that password with Wapp's existing password implementation;
- never displays or persists the plaintext bootstrap password;
- marks the User with `mustChangePassword=true`;
- cannot be run again after the OWNER membership exists.

The sealed bootstrap credential is deliberately unknowable. The first OWNER
therefore cannot be used for login until the mandatory finalization command
sets the real password.

## Password finalization

The final password is not accepted through a command-line argument or
environment variable.

The production wrapper reads it with hidden terminal input, verifies the two
entries match, then sends it to the application container only through STDIN.

The policy requires:

- 14 to 256 characters;
- at least 3 of lowercase, uppercase, number and symbol;
- the email local-part cannot be embedded in the password.

The finalizer only works while `mustChangePassword=true`. After success it
writes the Wapp password hash and atomically clears the flag. A second
finalization attempt is rejected.

## Migration

RH5 adds one backward-compatible User column:

```text
mustChangePassword Boolean @default(false)
```

Existing users receive `false`; normal authentication behavior is therefore
unchanged.

The migration is:

```text
20260902170000_first_owner_bootstrap
```

## Production workflow

After production migrations and images are deployed, inspect the state:

```bash
pnpm prod:first-owner:status
```

A new installation should report `EMPTY`.

Create the sealed identity:

```bash
pnpm prod:first-owner:bootstrap
```

The operator is prompted for:

- OWNER email;
- OWNER name;
- Company name;
- exact confirmation phrase `CREATE FIRST OWNER`.

No password is requested or displayed during this phase.

Then immediately finalize the OWNER password:

```bash
pnpm prod:first-owner:finalize
```

The password is entered twice with terminal echo disabled.

Finally:

```bash
pnpm prod:first-owner:status
```

must report `READY`.

## Legacy or partial databases

If users, companies or memberships already exist but no OWNER exists, RH5
stops.

That state requires an explicit data-migration decision. The first-owner
bootstrap must not silently attach itself to an arbitrary company or user.

## Automated drill

```bash
pnpm rh5:first-owner:drill
```

The drill uses a disposable MySQL 8.4 container with no named volume. It applies
the complete migration history and proves:

1. initial state is `EMPTY`;
2. sealed OWNER bootstrap succeeds once;
3. state becomes `PENDING_PASSWORD_FINALIZATION`;
4. a second bootstrap is rejected;
5. password finalization through STDIN succeeds;
6. state becomes `READY`;
7. a second password finalization is rejected.

The drill never touches production.

## Production safety

RH5 does not create a default username/password pair in source code, a seed
file or an environment template.

There is no reusable production seed credential.

Production bootstrap/finalization should be performed once, from a controlled
terminal session, after database migrations and before handing the installation
to users.
