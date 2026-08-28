# P3.2 CRM pipelines

P3.2 introduces company-defined relationship pipelines without changing the
operational ticket lifecycle.

`Ticket.status` remains:

- PENDING
- OPEN
- CLOSED

A CRM pipeline answers a different question: where is this contact in a
commercial, onboarding, renewal or other relationship journey?

## Multiple pipelines

A company may maintain multiple active pipelines.

Each pipeline owns its stages.

A contact may have one current stage per pipeline.

Removing a contact from a pipeline is represented as `stageId = null` at the
API level and deletes only the current state row. Transition history remains.

## Stage outcomes

Stages support:

- OPEN
- WON
- LOST

Outcome is metadata for later P3 reporting and segmentation. It does not close
a Wapp ticket.

## History

Every real movement creates an immutable `ContactStageTransition`.

No-op updates to the same stage do not create duplicate transition history.

Transitions preserve:

- contact;
- pipeline;
- previous stage;
- next stage;
- acting membership;
- timestamp.

## RBAC

All operational roles can:

- read pipelines;
- move contacts between stages.

OWNER / ADMIN / SUPERVISOR can also:

- create pipelines;
- create stages;
- activate/deactivate configuration.

AGENT cannot change the shared pipeline schema.

A stage with current contacts cannot be deactivated until those contacts are
moved elsewhere.

## Board

`/dashboard/pipeline`

The board:

- has one column per stage plus "Sem etapa";
- supports drag/drop on desktop;
- always exposes a stage select, including for touch/mobile;
- shows up to 80 recent contacts per column and tells the user when a column is
  truncated;
- links cards back to the contact and the latest ticket;
- listens to `contact.pipeline.updated` through Wapp realtime.

## Contact profile

The Contacts screen gets a Pipeline section with:

- current stage in every active pipeline;
- direct stage movement;
- recent stage-transition history;
- link to the full board.

## API

- GET `/api/v1/pipelines`
- GET `/api/v1/pipelines/manage`
- POST `/api/v1/pipelines`
- PATCH `/api/v1/pipelines/:id`
- POST `/api/v1/pipelines/:id/stages`
- PATCH `/api/v1/pipeline-stages/:id`
- GET `/api/v1/pipelines/:pipelineId/board`
- POST `/api/v1/contacts/:id/pipeline-stage`
- GET `/api/v1/contacts/:id/pipeline-states`

## Migration

P3.2 introduces:

- `CrmPipeline`
- `CrmStage`
- `ContactPipelineState`
- `ContactStageTransition`
- `CrmStageOutcome`
