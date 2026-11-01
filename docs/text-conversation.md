# Text Conversation and Local Memory

Status: first text conversation and confirmed local-memory implementation complete; the 2026-11-01 native-footwear correction restores the full 217-test Simulator pass. Authenticated API/persona evaluation and headset acceptance remain unverified. Ordinary Xiaomi MiMo pay-as-you-go API access is used. Last updated: 2026-11-01.

## Scope and ownership

The conversation window provides interruptible streaming text with a versioned adaptation of the [Columbina profile](characters/columbina.md). It coexists with the spatial preview but does not drive joints, expressions, sensing, or speech. The initial model is `mimo-v2.6-flash`; a settings picker allows an explicit Pro comparison through the same adapter. Thinking is disabled for both dialogue and extraction. See the [provider review](providers/xiaomi-mimo.md) for official sources.

- `ConversationModel` coordinates turns, configuration, cancellation, context invalidation, and memory proposals.
- `ConversationPrompt` bounds outbound context and distinguishes the configured relationship, active confirmed memories, and unsupported observations.
- `MiMoConversationService` owns the fixed HTTPS endpoint and provider protocol; an injectable line transport supports deterministic tests without paid calls.
- `MemoryLibrary` owns confirmed records, validation, revisions, retrieval, and storage availability. `FileMemoryStore` performs versioned atomic persistence.
- `KeychainAPIKeyStore` stores only the developer's own pay-as-you-go key on this device. Non-secret settings use application preferences.

## User flow

1. Open the conversation tab and configure an ordinary MiMo API key in the settings sheet. A blank key field preserves an existing key; key removal is explicit. No request is sent merely by opening the app or saving settings.
2. Send a Chinese message, watch the reply stream, and stop or supersede it if needed. Interrupted and failed replies remain visibly incomplete and are excluded from later conversation context.
3. Select memory extraction on a current user utterance. This makes one additional model request containing that utterance, not the entire conversation or memory database.
4. Review the proposed topic, fact, and verbatim evidence. Edit the proposal if needed, then explicitly confirm a new record or replace an existing record. A null result means no suitable stable preference was found.
5. Review, correct, individually delete, or clear confirmed memories in the memory sheet. Disabling future writes preserves existing records and recall but prevents extraction, confirmation, and editing. Deletion remains available.

Automatic background extraction, arbitrary episodes, semantic embeddings, full transcript persistence, voice, and automatic character actions are outside this increment. The explicit extraction action avoids silently treating every conversation as a durable-memory source or charging a second request for every reply.

## Memory integrity and privacy

The initial store contains bounded, user-confirmed semantic preferences/facts. Each record has a stable identifier, revision, topic, content, creation/update times, and self-contained evidence with the source utterance identifier and quote or an explicit manual-correction origin. Correction replaces the current value atomically; previous values are not retained as a hidden memory history.

The store has a schema version, size/count/field limits, unique identifiers/topics, and explicit error handling. Unsupported or damaged files are not overwritten automatically. Retry loading or explicitly clear and rebuild the store from the memory sheet. Failed writes leave the previously published records unchanged.

Current limits are 100 records, a 512 KiB file, 60-character topics, 300-character facts, and 400-character evidence quotes. Recall selects at most eight records. Each dialogue includes at most six complete historical turns within 6,000 characters, plus the current input of at most 2,000 characters. These are character/data bounds, not exact token estimates. The per-request output cap is 768 tokens; hitting it leaves the reply visibly incomplete.

Memory changes invalidate the current request, pending proposal, and previous conversation context. Existing on-screen text can remain for inspection, but pre-change utterances cannot be extracted again and are not sent in later dialogue requests. A new conversation discards all ephemeral turns and proposals while retaining confirmed memories. A process restart also discards chat turns; confirmed records contain their own minimal evidence.

Dialogue sends the curated persona, configured display name, bounded complete recent turns, current input, and a bounded selection of confirmed memory facts. The first small collection uses local lexical ranking with a recency fallback, not model embeddings. Evidence quotes stay local during ordinary recall. Extraction sends only the selected source utterance and the extraction contract. No audio, room geometry, model files, complete memory database, or credentials enter prompt text.

Memory files live in application support with atomic replacement and backup exclusion. The application sandbox and platform data protection apply; this is not application-managed encryption. Local deletion does not purge previously transmitted provider copies. The settings sheet explains the outbound data boundary before the user sends a message.

## Cancellation and errors

Each operation has an identifier and memory revision. Stop, a new request, settings changes, memory mutations, a new conversation, and app backgrounding invalidate old work. App-level scene phase handles backgrounding across multiple windows rather than cancelling shared work when just one window becomes inactive. Cancellation propagates to networking, while identifier checks independently reject late chunks and extraction results. A new request never silently retries a paid generation.

Handle authentication, access/balance, rate limits, network timeout, server failure, malformed streams, missing completion, truncation, unsupported tool output, and provider rejection without displaying raw provider bodies. Parse SSE events across lines, ignore reasoning, and require an explicit successful finish plus visible answer content before marking a turn complete. Truncated JSON or an unsupported evidence reference cannot produce a memory proposal.

## Verification

Automated tests must cover request construction, bounded context, persona/capability rules, SSE framing, error mapping, cancellation and stale results, proposal evidence, restart recall, correction/deletion, write disabling, storage corruption/versions, and failed writes. Use injected credentials and scripted transports; never require a real key or paid request for tests.

Simulator/device SDK builds verify integration. Paid API access, model persona quality, actual latency, and physical-headset readability require a separate user-run check with their locally entered key. Record those as unverified until observed.

### Run and accept on the headset

1. Build and run the shared `Bina` scheme with normal Xcode signing. Do not disable signing for an interactive Keychain check. Unsigned Simulator builds can compile while lacking the application identity required by Keychain; see Apple's [missing-entitlement guidance](https://developer.apple.com/documentation/security/errsecmissingentitlement).
2. In conversation settings, enter the ordinary pay-as-you-go key and optional display name. Keep Flash initially. Saving settings does not make a request.
3. Exchange several ordinary Chinese messages, interrupt one answer, then send a replacement. Verify old text does not resume or become part of a later answer.
4. State a simple drink preference. Extract from that utterance, inspect the quoted evidence, and confirm the fact. Check the memory list, restart the process, and ask a paraphrased recall question.
5. Correct the record in the memory sheet, then ask again. Delete it and verify the old fact is no longer supplied; previous on-screen conversation is excluded from the next request. Missing recall must not turn into an invented shared episode.
6. Disable writes, verify recall/deletion still work, and test an invalid key or disconnected network. No failed save should be reported as successful.
7. Use the separate character-and-space tab for the existing spatial preview. Text replies do not yet animate or speak through the character.

### Results on 2026-10-31

Toolchain: Xcode 27.2 (27B52), SDK 27.2. Tests use synthetic utterances and isolated credentials; no authenticated model call or paid request was made.

| Check | Result |
| --- | --- |
| New text/memory suites on visionOS Simulator 27.2 | 60 passed, zero failures/skips or reported runtime warnings. Includes real Keychain save/replace/remove under a unique test service, actual URLSession framing through an intercepting URLProtocol, cancellation, bounded output, evidence, persistence, and stale writes. `/private/tmp/Bina-Conversation-Final.xcresult`. |
| Signed Simulator build for testing | Passed after final app-level background-cancellation wiring. `/private/tmp/Bina-Conversation-final-build.log`. |
| Generic visionOS device SDK build | Passed with signing disabled; not an installation or a headset run. `/private/tmp/Bina-Conversation-device-complete.log`. |
| Signed standalone Simulator launch | The 27.2 conversation screen, setup prompt, memory entry point, composer, and data notice rendered without the unsigned build's Keychain error. Desktop automation could not complete embedded visionOS control clicks; settings/proposal dialog interaction remains a headset acceptance item. |
| Full Simulator 27.2 regression attempt | Earlier 208-test snapshot: 194 passed and 14 existing bundled-character tests ended with signal kill. `/private/tmp/Bina-Conversation-Full.xcresult`. This is not a full-suite pass. |
| Full Simulator 27.0 comparison | 211 tests: 197 passed, 14 bundled-character tests ended with signal kill, zero skips. `/private/tmp/Bina-Conversation-Full-27_0.xcresult`. All 60 new tests passed. |
| Unmodified spatial baseline | An isolated archive of commit `2c4cf3f`, with the same existing local assets, reproduced the failing facial case on 27.2. `/private/tmp/Bina-Conversation-Baseline-Smoke.xcresult`. A fresh 27.2 Simulator also reproduced it while passing all then-current 58 new tests. |

Those failing character cases coincided with `backboardd` terminating in `IndexValidation._validate_neon`, `DRValidateIndices`, and `REMultiBufferMeshPayload` decoding. The [2026-11-01 investigation](footwear-mesh-investigation.md) verifies the original 151-test pass, reproduces failures with its preserved binaries, and isolates a trigger to barefoot-mesh generation in `CharacterFootwear`. The original character resources and geometry code were not changed by conversation integration, but the new tab structure can change character-loading timing. Its causal role in the transition remains unproved; neither user environment changes nor an Apple-only cause have been established.

Unsigned Simulator builds initially failed Keychain access. A normal signed build passed the real isolated Keychain test; use normal Xcode signing for interactive setup. Live MiMo account/model availability, API response behavior, Chinese portrayal, latency, and headset UI/recall remain unverified until the user runs the acceptance steps above.

### Full regression restored on 2026-11-01

The footwear correction replaces runtime imported-mesh reconstruction with native loading of a paired, locally authored USD layer. The full visionOS Simulator 27.2 suite passes all 217 tests, with zero failures/skips or reported runtime warnings, at `/private/tmp/Bina-Footwear-Native-Fix-Full.xcresult`. This includes all 60 conversation/memory tests, the previously interrupted character cases, and six new footwear/profile regressions. Focused tests and the generic device SDK build also pass; see the [complete verification](footwear-mesh-investigation.md#correction-verification-on-2026-11-01). No authenticated API call was required. Headset and live-provider acceptance remain open.
