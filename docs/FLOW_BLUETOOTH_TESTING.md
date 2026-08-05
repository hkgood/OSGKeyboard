# Flow Bluetooth HFP release gate

Run this checklist on a physical iPhone before every release that changes Flow,
PiP, ASR warmup, or audio-session code. Simulator audio is not an HFP substitute.

## Required devices

- Built-in iPhone microphone
- One Bluetooth HFP headset (AirPods or equivalent)

## Pass criteria

1. Start a PiP Flow session and record 50 consecutive utterances with the
   built-in microphone.
2. Repeat 50 utterances with the Bluetooth headset already connected.
3. Switch Prompt in the host app, return to the original text field, and record
   20 more Bluetooth utterances.
4. During recording, connect and disconnect the headset once. The app must
   recover automatically before speech starts, or stop with an explicit
   audio-device-changed error after speech has started.
5. Recreate the keyboard extension once while processing and once after the
   Host writes the final result.

The run fails if any of the following occurs:

- `-10868` or `formats don't match`
- `capture.engine.startFailed`
- A completed utterance reports zero input frames
- `host.delivered` has no matching `keyboard.insert`
- The same utterance is inserted more than once
- A background task exceeds 30 seconds
- AVAudioSession activation blocks the main thread

Archive the filtered `[trace]` log with the release test record.
