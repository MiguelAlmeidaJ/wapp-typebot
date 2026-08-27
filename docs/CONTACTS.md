# Contacts

P1.1 turns the automatically-created WhatsApp contact into an application
profile.

## Name ownership

`Contact.name` is the display name chosen inside Wapp.

`Contact.whatsappName` is the latest push name received from WhatsApp.

Incoming messages may refresh `whatsappName`, but must never overwrite a name
that an operator edited in Wapp.

## Profile fields

- name
- whatsappName
- phoneNumber
- email
- notes
- lastSeenAt
- isGroup

## Search

Contacts can be searched by:

- Wapp name
- WhatsApp name
- phone
- remoteJid
- email

and filtered between people, groups or all contacts.

## History

The profile exposes recent tickets and aggregate counts for tickets, active
tickets and messages.

P1.1 intentionally does not create contacts manually or initiate new outbound
conversations. That requires choosing a WhatsApp connection and validating the
destination and belongs in a later contacts milestone.
