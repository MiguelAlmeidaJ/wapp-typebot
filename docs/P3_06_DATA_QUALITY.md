# P3.6 Import/export and data quality

P3.6 closes the functional P3 roadmap with safe CSV workflows.

No database migration is introduced by this milestone.

## Import safety model

Import is a two-step process:

1. preview;
2. explicit commit.

The preview classifies every CSV row as:

- `CREATE`;
- `UPDATE`;
- `CONFLICT`;
- `INVALID`;
- `SKIP`.

The server returns a SHA-256 fingerprint derived from the resolved plan,
including row status and the currently matched contact IDs.

Commit recomputes the plan from the same CSV and mapping. If contact data
changed enough to alter the plan, the fingerprint changes and commit is
rejected with `IMPORT_PREVIEW_CHANGED`.

This prevents a previously reviewed preview from silently committing against a
different duplicate state.

## Limits

Initial import limits:

- 500 data rows per CSV;
- 40 columns;
- 650,000 CSV characters so the request stays below the API's 1 MiB body
  limit with JSON overhead;
- 10,000 characters per individual cell.

Large imports must be split into explicit batches.

## Contact identity

One column must map to phone / WhatsApp.

The importer normalizes the number and creates the canonical phone JID:

`<digits>@s.whatsapp.net`

A configurable default country code is used only for local numbers containing
10 or 11 digits without a leading `+`.

For the Brazilian default:

`(11) 99999-8888` -> `5511999998888@s.whatsapp.net`

Numbers already supplied with `+` are treated as international numbers and are
not prefixed again.

The existing database invariant remains authoritative:

`@@unique([companyId, remoteJid])`

## Duplicate review

The importer never automatically merges ambiguous contacts.

Exact `companyId + remoteJid` matches become `UPDATE`.

The following become `CONFLICT`:

- the normalized phone is already attached to a different remote JID;
- the normalized e-mail is already attached to another contact.

Repeated phone identities inside the same CSV become `SKIP` after the first
occurrence.

The Data Quality screen also scans up to 5,000 existing direct contacts and
surfaces possible phone/e-mail duplicate groups for manual review.

No automatic merge endpoint exists in P3.6.

## Field mapping

Supported standard targets:

- name;
- phone / WhatsApp;
- e-mail;
- notes.

P3.1 custom fields can be mapped individually.

The same existing value rules are used for TEXT, NUMBER, DATE, BOOLEAN and
SELECT fields.

Required custom fields are checked against the final value. Existing values
may satisfy a required field during an update.

P3.2 pipelines can be mapped one column per pipeline. The CSV cell contains
the stage name. Only active stages are eligible.

Pipeline changes created by import also create the normal
`ContactStageTransition` history with the importing membership as actor.

Each committed row executes in its own database transaction so a row cannot
finish half-applied across Contact, custom fields and pipeline state.

## Campaign consent boundary

Campaign consent is intentionally not an import target.

CSV import never creates or changes `ContactCampaignConsent`.

A contact imported from an external list therefore remains `UNKNOWN` for
campaign purposes until explicit authorization is recorded through the normal
P3.5 consent workflow.

This prevents CSV upload from bypassing the controlled-campaign safety model.

## Export

Managerial users can export up to 5,000 direct contacts per request.

The export includes:

- name;
- phone;
- e-mail;
- notes;
- remote JID;
- last interaction;
- campaign consent state;
- active custom-field values;
- current stage in active pipelines.

Spreadsheet formula injection is neutralized. Cells beginning with `=`, `+`,
`-` or `@` are prefixed with an apostrophe before CSV encoding.

Import and export operations write summarized `CONTACT_DATA` audit events. Raw
CSV content is never written into the audit log.

## RBAC

OWNER / ADMIN / SUPERVISOR:

- read Data Quality;
- preview imports;
- commit imports;
- export contact data;
- review duplicate candidates.

AGENT has no P3.6 access.

## API

- GET `/api/v1/data-quality/context`
- POST `/api/v1/data-quality/import/inspect`
- POST `/api/v1/data-quality/import/preview`
- POST `/api/v1/data-quality/import/commit`
- POST `/api/v1/data-quality/export`

## UI

`/dashboard/data-quality`

The page contains:

- data quality counters;
- CSV selection and column mapping;
- import preview and row selection;
- explicit `IMPORTAR CONTATOS` confirmation;
- safe CSV export;
- existing duplicate review links.
