# Media pipeline

P1.2 adds binary media handling without storing files inside MySQL.

```text
Evolution MESSAGES_UPSERT
        |
        v
Message row
mediaStatus=PENDING
        |
        v
background capture
        |
        +--> Evolution getBase64FromMediaMessage
        |
        v
.runtime/media/<company>/<message>.<ext>
        |
        v
mediaStatus=READY
        |
        v
authenticated GET /api/v1/messages/:id/media
```

## Stored in MySQL

- mediaStatus
- mediaStorageKey
- mediaSize
- mediaMimeType
- mediaFileName
- mediaError

The binary is not stored in the database.

## Local storage

Development uses `.runtime/media`.

Production should replace the storage adapter with S3-compatible object
storage. The domain does not expose the local path to the browser.

## Security

Media delivery checks the authenticated user's company before reading the file.
The browser retrieves media through authenticated fetch and creates a temporary
object URL.

## Retry

A failed media message can be retried with:

`POST /api/v1/messages/:id/media/retry`

A media capture failure must never prevent the text/message metadata from
reaching the inbox.
