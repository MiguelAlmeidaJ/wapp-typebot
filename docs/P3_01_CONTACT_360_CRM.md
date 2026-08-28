# P3.1 Contact 360 CRM

P3.1 extends the existing Contacts module instead of replacing it.

Existing Wapp identity rules remain unchanged:

- `Contact.name` is the manual Wapp display name;
- `Contact.whatsappName` remains provider identity;
- incoming provider names must not overwrite a deliberate manual Wapp name.

## Custom fields

Company-level definitions support:

- TEXT
- NUMBER
- DATE
- BOOLEAN
- SELECT

Definitions have:

- generated stable key;
- label;
- type;
- SELECT options;
- required flag;
- position;
- active/inactive state.

Only OWNER / ADMIN / SUPERVISOR have `contactFields.manage`.

Existing `contacts.manage` continues to control editing values on a contact.

Field type is immutable after creation. This avoids silently invalidating
existing stored values.

## Values

Values are stored per contact + field with one unique row.

Blank optional values remove the row.

Required fields are validated against the final contact state, not only the
fields submitted in the current request.

## Contact timeline

The CRM profile consolidates recent:

- messages;
- immutable ticket operational events;
- internal notes.

The API does not expose raw WhatsApp payloads.

Timeline items deep-link back to the corresponding Wapp ticket.

## API

- GET `/api/v1/contact-crm/fields`
- GET `/api/v1/contact-crm/fields/manage`
- POST `/api/v1/contact-crm/fields`
- PATCH `/api/v1/contact-crm/fields/:id`
- GET `/api/v1/contacts/:id/crm`
- PUT `/api/v1/contacts/:id/crm-fields`

## Migration

P3.1 introduces:

- `ContactFieldDefinition`
- `ContactFieldValue`
- `ContactFieldType`
