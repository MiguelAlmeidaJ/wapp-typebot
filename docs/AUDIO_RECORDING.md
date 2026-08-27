# Browser audio recording

P1.4 adds microphone capture to the existing P1.3 outbound-media flow.

No new API route or database migration is required.

## Flow

```text
operator clicks microphone
        |
        v
getUserMedia(audio)
        |
        v
MediaRecorder
        |
        v
Blob / File
        |
        v
local audio preview
        |
        v
existing P1.3 multipart upload
        |
        v
Evolution sendMedia
        |
        v
WhatsApp
```

## Browser formats

Wapp selects the first format supported by the browser from:

1. `audio/ogg;codecs=opus`
2. `audio/webm;codecs=opus`
3. `audio/webm`
4. `audio/mp4`

The server already normalizes MIME parameters before classifying outbound audio.

## UX and failure behavior

- Recording requires explicit microphone permission.
- The operator can stop or cancel a recording.
- After stopping, the recording becomes the selected attachment.
- The recording can be played before sending.
- The selected recording is preserved when the API/Evolution send fails.
- The existing 25 MiB upload limit still applies.

P1.4 sends the capture through the normal audio-media path. A future milestone
can introduce WhatsApp-native PTT/voice-note semantics if required.
