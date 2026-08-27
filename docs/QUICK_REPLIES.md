# Quick replies

P1.7 adds a shared company library of reusable replies.

## Usage

All operational roles can read/use active quick replies.

The operator can:

- click the quick-reply button in the composer;
- type `/` followed by a shortcut or search term;
- select a reply;
- review or edit the expanded text;
- send it through the normal message flow.

Selecting a reply never sends automatically.

## Management

OWNER, ADMIN and SUPERVISOR can:

- create;
- edit;
- activate;
- deactivate.

AGENT can only read/use the active library.

Replies are soft-disabled rather than deleted.

## Variables

The following variables are expanded when a reply is inserted into the
composer:

- `{{nome}}`
- `{{primeiro_nome}}`
- `{{atendente}}`
- `{{empresa}}`

Expansion happens at insertion time using the selected ticket and current
session.

## Shortcuts

A shortcut is company-unique, case-insensitive after normalization, and stored
without the leading slash.

Examples:

- `/saudacao`
- `/prazo`
- `/pix`
- `/encerramento`

Allowed shortcut characters:

- letters
- numbers
- hyphen
- underscore

## Realtime

Library changes publish:

`quick-reply.updated`

Other open Wapp sessions refresh the active quick-reply library automatically.
