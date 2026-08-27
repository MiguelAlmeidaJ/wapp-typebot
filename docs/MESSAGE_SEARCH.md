# Message history search

P1.9 adds server-side historical search for Wapp conversations.

## Scope

Operators can search:

- all company message history;
- only the currently selected ticket.

The search checks:

- message body;
- media file name;
- contact name;
- contact phone number.

The query runs against MySQL, not only against the 200 messages currently
loaded in the Conversations UI.

## Endpoint

`GET /api/v1/messages/search`

Parameters:

- `q`: required, 2-160 characters;
- `ticketId`: optional;
- `page`: default 1;
- `limit`: 10-50, default 30.

Results are company-scoped by authenticated session.

## Closed tickets

Historical results can include closed tickets.

P1.9 displays those results but does not reopen them from search. Active
tickets can be opened directly from the result.

A future archived-ticket workflow can add navigation for closed tickets
without coupling search to ticket reopening.

## Performance

P1.9 intentionally uses Prisma `contains` / SQL LIKE for correctness and
simplicity at the current scale.

Existing indexes on company, ticket and timestamp continue to help scope the
queries, but body matching itself is not full-text indexed.

When message volume becomes large, this service is the boundary where MySQL
FULLTEXT or a dedicated search engine can be introduced without changing the
UI contract.
