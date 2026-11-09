# Push-to-Talk Conversation

Status: first implementation complete. On 2026-11-03 the user reported that the basic functions work after this increment. Treat this as a preliminary functional pass; no itemized capture/playback checklist, voice selection, latency measurements, installed revision, or device build accompanied the report. Detailed acoustic quality, interruption timing, failure recovery, and sustained performance remain open. Automated evidence from 2026-11-02 is recorded below.

## Experience and scope

Hold the microphone control to record, release to transcribe, review/edit the recognized text, then explicitly send and hear the reply. Accessible start/finish controls provide the same recording flow. Voice selection and an explicit audition use two Chinese preset voices. Ordinary typed conversation remains available; automatic reading of typed replies is opt-in.

The first increment requests one complete WAV after a complete model reply, rather than streaming partial sentences into a playback queue. This bounds ordering and cancellation while preparing the full path for headset validation. Automatic endpointing, full-duplex capture, voice cloning, detailed visemes, and persistent emotional state are outside this increment.

## Ownership and flow

- `SpeechSession` owns recording, transcription review, speech intent, turn identity, synthesis, playback state, subtitle text, and cancellation. It observes explicit conversation lifecycle events; it does not own memory or the language-model adapter.
- `SpeechRecording` isolates permission and temporary microphone capture. Capture is bounded to 30 seconds and stops before any playback can start.
- `MiMoSpeechService` implements separate ASR and TTS calls behind `SpeechServing`. It uses the existing ordinary pay-as-you-go key and fixed HTTPS origin. Redirects, unsupported responses, oversized data, and incomplete results are rejected.
- `SpeechPlaying` isolates actual playback. The live adapter uses RealityKit spatial audio near the placed character's head when available, and clearly identified window playback otherwise. Preparation is cancellable; late resource completion cannot restart stopped audio.
- `SpeechAudioSession` serializes asynchronous native activation and deactivation shared by capture and playback. Audio stops synchronously at the player/recorder boundary, while hardware teardown drains in order. A late deactivation cannot disable a newer recording. This avoids main-thread blocking from synchronous `setActive` calls.
- `ConversationModel` continues to own dialogue, credentials, memory/context revisions, and text cancellation. A weak lifecycle observer lets speech stop on new requests, memory mutations, settings changes, or a new conversation. Audio failure preserves the displayed answer.
- The existing face controller remains the sole facial writer. Listening/thinking cues, validated dialogue expression, and a bounded audio-energy mouth overlay preserve the selected eye form. A manual expression override remains available. Mouth motion follows actual playback time, not model token timing. This is approximate jaw motion, not phoneme lip-sync. See [Dialogue expression](dialogue-expression.md) for the 2026-11-03 facial/vocal coordination and short-term continuity increment.

## State and interruption

The visible states are idle, permission request, recording/listening, transcribing, review, model thinking, synthesis preparation, and speaking. Speaking begins only when playback starts. Subtitles show the complete currently played answer; they are not word-aligned captions.

Stop, a new recording/turn, settings changes, memory changes, app backgrounding, audio interruption, and immersive disappearance invalidate the operation identity, cancel network work, close/discard capture, stop playback, and clear speaking cues. Late callbacks must check their identity before changing state or playing audio. Capture cannot run alongside character audio. Tracking/visibility loss cancels an active spatial interaction. A cancelled interaction never resumes automatically.

Generated text, speech preparation, actual playback, completed playback, and interruption are distinct turn states. A reply intended for speech is excluded from future shared context until playback completes. An interrupted or failed spoken reply remains readable but cannot silently count as a fully heard reply. Memory extraction still requires review and confirmation of a user utterance; raw recordings and unreviewed ASR output never become durable memories.

## Provider and data contract

The [ASR guide](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/Speech-Recognition) documents `mimo-v2.5-asr`, WAV/MP3 input encoded as Base64, and a 10 MB encoded-input limit. Use explicit Chinese recognition for this first profile. The [TTS guide](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/speech-synthesis-v2.5) documents `mimo-v2.5-tts`, Chinese preset IDs `冰糖` and `茉莉`, assistant-role synthesis text, and Base64 audio in the response. This prototype requests non-streaming WAV and validates PCM16 audio before playback. API availability and perceived voice quality require authenticated device checks.

Only the explicit recording is sent to ASR. TTS receives the answer text and one of five fixed local delivery instructions selected by validated affect, not arbitrary model instructions, the memory database, or the recording. The private expression header is never synthesis text. Dialogue retains its bounded persona/context/memory request with optional local expression continuity. Raw microphone files are temporary and removed on finish/cancel; abandoned WAV files in this feature's own temporary directory are removed when recording next starts after a process exit. Audio and transcript drafts are not persistent chat history. No audio is collected on launch, and no request is made merely by changing a voice. Audition and synthesis are additional paid API operations initiated by the user flow.

Capture uses mono 16 kHz PCM16 WAV, at most 30 seconds and 1,024,000 bytes, below the provider limit. Recognized text is bounded by the existing 2,000-character composer limit. Synthesis accepts at most 4,000 characters; playback accepts validated PCM16 WAV at 8–48 kHz, one or two channels, at most 120 seconds and 12 MiB. Unusual WAV encodings are rejected instead of handed unchecked to the renderer. These are local limits, not promises about provider limits or reply latency.

## Verification and headset acceptance

Automated coverage must exercise request/response contracts, audio bounds and WAV validation, denied permission, release during permission, cancelled ASR/TTS, stale callbacks, recording limit, transcript review, memory/settings invalidation, playback failure, completed versus interrupted spoken context, and scene/audio lifecycle. Use scripted services and synthetic audio; never require a real key or paid request for regression tests. Preserve all spatial and footwear regressions.

On the headset, explicitly grant or deny microphone access; try hold/release and accessible start/finish, correct a character name, send and hear a reply, audition both voices, and test stop/new-turn/background/space-exit behavior during each stage. Verify the character's audio position while moving around her, subtitles, both eye forms, mouth closure after stop, pause/reference controls, and recovery after a network or audio-route interruption. Record first-audio latency and interruption-to-silence time. Compilation and scripted tests do not establish these physical-device results.

First permission interaction: releasing the control while permission is pending cancels that attempt. Grant permission, then hold again; capture must never begin after the user has released the control. Immersive playback requires a placed, visible character in natural playback mode; otherwise the panel identifies window playback. Spatial timing uses RealityKit's scheduled host time and playing state; window timing uses `AVAudioPlayer.currentTime`. Neither supplies validated phoneme alignment or measured acoustic latency.

### Automated delivery record

This record predates the user's 2026-11-03 decision to raise the minimum to visionOS 27.2. The 27.0 run and bundled minimum values below describe those preserved builds. Routine verification now follows the [27.2 deployment policy](platform-capabilities.md#local-project-baseline).

Toolchain: Xcode 27.2 (27B52), SDK 27.2. The complete preceding 217 tests are retained, with 34 new speech, lifecycle, native playback, and character-cue cases. Tests use synthetic utterances, isolated credentials, scripted provider results, intercepted URLSession requests, and silent PCM audio. No authenticated ASR/TTS request, real microphone capture, or paid model call was made.

| Check | Result |
| --- | --- |
| Full visionOS Simulator 27.2 regression | 251 passed, zero failures/skips or reported runtime warnings. `/private/tmp/Bina-Voice-Release-Full.xcresult`. |
| Independent visionOS Simulator 27.0 voice regression | All 34 new cases passed, zero failures/skips or reported runtime warnings, on OS build 24M362. Verifies native asynchronous audio, response bounds, cancellation, review, and both eye forms at the then-minimum supported OS. `/private/tmp/Bina-Voice-Release-27_0.xcresult`. This is a focused run, not a second complete suite. |
| Native audio and hardware-transition probes | Six passed with no reported runtime warnings. Includes RealityKit WAV import, actual silent window playback/completion, stop suppressing an obsolete completion, ordered hardware transitions, recovery, and cancellation during microphone activation without starting capture. `/private/tmp/Bina-Voice-Preload.xcresult`. |
| Simulator test build | Passed with normal ad-hoc identity. `/private/tmp/Bina-Voice-Preload-build-2.log`. |
| Generic visionOS device SDK build | Passed with signing disabled; not a headset installation or run. `/private/tmp/Bina-Voice-Release-Device.log`. |
| Bundled resources and permissions | All six character resources match the local source in both built apps. Microphone and world-sensing purpose strings are present, with the 27.0 minimum target retained. `LocalAssets/Voice/2026-11-02/resource-verification.json`. |
| Automated UI capture | `simctl` timed out waiting for screen surfaces. No completed graphical walkthrough, hold-gesture validation, or headset readability check is claimed. |

Earlier complete passes exposed nine main-thread audio-session warnings, then two after asynchronous activation alone. The correction moves native session configuration and activation away from the scene actor and serializes hardware transitions. Window-player preloading, which can activate audio internally, also runs off the UI actor within that same queue. The final native probes and full suite have no reported runtime warnings; the earlier results are not substituted for the final verification.

Headless Simulator console messages about unavailable room-congruence/personalized spatial-audio services still appear during native audio tests. Silent window playback and WAV import do not validate headset acoustics. Account access, actual recorded Mandarin/character names, gesture behavior, voice quality, spatial sound, subtitles, and interruption latency remain the explicit headset acceptance gate above. Local result summaries and source fingerprints are retained under `LocalAssets/Voice/2026-11-02/`.
