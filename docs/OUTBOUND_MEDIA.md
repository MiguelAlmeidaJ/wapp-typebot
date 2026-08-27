# Outbound media

P1.3 adds attachment sending from the Wapp operator composer.

Supported initial categories:

- image
- audio file
- video
- document

Browser audio recording is intentionally not part of P1.3.

## Flow

```text
operator selects file
        |
        v
browser preview
        |
        v
multipart/form-data
POST /api/v1/tickets/:id/media
        |
        v
ticket assignment + connection validation
        |
        v
Evolution /message/sendMedia/:instance
        |
        v
WhatsApp
        |
        v
Message OUTBOUND
mediaStatus=READY
        |
        v
local media storage + realtime
```

## Security and limits

The route reuses the authenticated ticket context and ticket assignment rules.

The default maximum upload size is `MEDIA_MAX_BYTES` (25 MiB in the current
development configuration).

The API accepts a conservative list of image, audio, video and document MIME
types. HTML and SVG are intentionally not accepted as uploadable documents.

## Failure semantics

The selected browser file is only cleared after the API succeeds.

If Evolution rejects the send, the operator keeps the selected attachment and
can try again.

If WhatsApp accepted the media but local storage fails afterward, the message
is persisted with `mediaStatus=FAILED`. The incoming media recovery path from
P1.2 can still be used as a fallback.
