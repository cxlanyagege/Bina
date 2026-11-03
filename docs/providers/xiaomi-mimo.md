# Xiaomi MiMo Evaluation for Bina

Status: the user selected ordinary pay-as-you-go access. The first native text adapter and confirmed local-memory loop are implemented, defaulting to V2.6 Flash with an explicit Pro comparison setting. See the [runtime contract](../text-conversation.md). Official documentation reviewed on 2026-10-31; no authenticated API calls, persona trials, live latency measurements, or audio tests were performed.

See [architecture](../architecture.md#persistence-and-services), [memory and emotion](../memory-and-emotion.md), the [Columbina profile](../characters/columbina.md), and [portrayal evaluations](../characters/columbina-evaluation.md). Existing spatial and facial controls do not establish conversational integration.

## Model selection

The current [official catalog](https://mimo.mi.com/docs/zh-CN/quick-start/summary/model) lists `mimo-v2.6-flash` and `mimo-v2.6-pro` with streaming, function calling, structured output, and a 1M-token context window. The V2.5 text models were retired on 2026-10-21; the separately named V2.5 ASR/TTS models remain listed. `mimo-v2.6-pro-ultraspeed` requires a custom service arrangement and is outside the initial experiment.

Start by evaluating Flash for ordinary Chinese companion dialogue, with Pro as a comparison using the same profile and scenarios. This is a project recommendation based on the available interface and cost, not evidence that Flash has lower measured headset latency or that either model portrays Columbina well. Keep the model ID configurable within one MiMo adapter rather than introducing automatic routing or multiple providers.

Both [Flash](https://mimo.mi.com/models/zh-CN/mimo-v2.6-flash) and [Pro](https://mimo.mi.com/models/zh-CN/mimo-v2.6-pro) accept multimodal input but return text. A large context window does not replace selective memory retrieval. Model capability does not grant Bina camera access or new visionOS sensing permissions.

## API and initial request

The [first-call guide](https://mimo.mi.com/docs/zh-CN/quick-start/summary/first-api-call) documents an OpenAI Chat Completions-compatible interface. For ordinary pay-as-you-go API access:

- Base URL: `https://api.xiaomimimo.com/v1`.
- Request: `POST /chat/completions`.
- Authentication: ordinary API key; the [integration FAQ](https://mimo.mi.com/docs/zh-CN/quick-start/faq/api-integration) accepts either `api-key` or `Authorization: Bearer`.

Use native Swift networking behind a narrow conversation-service interface; the SDK examples do not require adding Python or JavaScript to the visionOS application. Compatibility here concerns the documented wire format, not an assumption that Responses, Realtime, or every compatible SDK feature is available.

The implemented adapter uses the following request shape; the placeholder below stands for the versioned runtime persona and selected context. Request construction is tested without authenticated API access:

```json
{
  "model": "mimo-v2.6-flash",
  "messages": [
    {
      "role": "system",
      "content": "<curated Columbina portrayal, Simplified Chinese dialogue, memory provenance rules, and current capability limits>"
    },
    {
      "role": "user",
      "content": "<current user input>"
    }
  ],
  "stream": true,
  "thinking": { "type": "disabled" },
  "max_completion_tokens": 768
}
```

The output budget is provisional and must be tuned from measured replies, truncation, and cost. Do not copy the generic MiMo identity or hard-coded date from vendor examples into the character profile. Evaluate role fidelity explicitly; a model's general benchmarks do not establish persona fidelity.

The [thinking guide](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/text-generation/deep-thinking) says thinking is enabled by default. Disable it explicitly for the first daily-conversation trial to avoid unnecessary reasoning latency. When enabled, `max_completion_tokens` covers reasoning plus the answer, and streaming reasoning precedes answer content. Future thinking-enabled tool histories have additional `reasoning_content` replay requirements; account for these before enabling that combination.

Bina should display only answer content. Protocol reasoning is not a spoken line, durable personal memory, or evidence of an event. Measure time to the first visible answer content, separately from the first network byte or reasoning chunk.

## Ownership and integration

The proposed flow is:

1. Local code assembles the curated profile, bounded recent turns, relevant active memory excerpts, and supported capability descriptions.
2. The MiMo adapter streams reply text to the current conversation turn.
3. When needed, a separate extraction request proposes memory candidates after the reply; it does not block first-answer display.
4. Local code validates candidates, obtains the initial explicit confirmation, and performs versioned local persistence. The model cannot report a successful save before storage succeeds.

The [structured-output guide](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/text-generation/structured-output) provides `response_format: {"type":"json_object"}`. JSON mode does not establish adherence to Bina's field definitions or semantic rules. Accumulate a complete object before decoding; validate types, bounds, enumerations, and evidence references locally. Truncated or invalid output must not write memory or trigger an action.

Preserve source turns and the distinction between configured fictional relationships and actual shared history. Correction/deletion must invalidate cached retrieval and pending extractions. Reject results from obsolete turns or memory revisions. Store neither generated acknowledgments nor fictional lore as proof of a real event.

Likewise, future emotional or action proposals must pass the local capability allowlist and existing behavior coordination. They may request supported expression or attention changes; they cannot write RealityKit transforms, skeletal joints, or physics state directly. Start with text output before enabling model-driven gestures.

The adapter needs bounded input/output, incremental SSE parsing, cancellation, finish/error handling, and rejection of late chunks. Preserve an interrupted reply as interrupted rather than completed. Surface authentication, rate-limit, service, and content-policy failures distinctly enough to recover; do not fabricate a character reply or successful memory write. Default diagnostics should record timing, model, token counts, and request identifiers without logging private text or credentials.

## Cost and account choice

The [official pay-as-you-go price page](https://mimo.mi.com/docs/zh-CN/price/pay-as-you-go) lists these domestic real-time prices, in CNY per million tokens:

| Model | Input without cache | Cached input | Output |
| --- | ---: | ---: | ---: |
| `mimo-v2.6-flash` | 1.00 | 0.02 | 2.00 |
| `mimo-v2.6-pro` | 3.00 | 0.025 | 6.00 |

Illustration only: 1,000 requests, each with 4,000 input tokens and 200 output tokens, with no cache, cost approximately CNY 4.40 for Flash or CNY 13.20 for Pro. This is arithmetic, not a usage forecast. It excludes extraction requests, longer histories, reasoning, audio, and separately billed services. Tokens are not Chinese characters. Measure actual usage and cache hits before estimating a personal monthly budget; the account's region determines the applicable currency and rates.

Pay-as-you-go balances and Token Plan quotas are separate. Token Plan also uses different credentials and a different endpoint; obtain its actual base URL from the console. The [Token Plan overview](https://mimo.mi.com/docs/zh-CN/tokenplan) presents the plan for AI coding, so custom companion-app eligibility and current subscription restrictions require confirmation before relying on it. Begin planning with ordinary pay-as-you-go API access unless the user's existing account arrangement establishes otherwise.

## Speech is a separate evaluation

MiMo offers a possible single-vendor speech stack, but the text model alone is not an end-to-end spoken character:

| Stage | Candidate | Bina-specific constraint |
| --- | --- | --- |
| Speech recognition | `mimo-v2.5-asr` | The [ASR guide](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/Speech-Recognition) documents Chinese/English, Base64 WAV/MP3 input, and streamed transcription output. Streaming results from a submitted recording do not establish continuous microphone upload or full-duplex behavior. Test Chinese names, quiet speech, echo, and code-switching on Vision Pro. |
| Speech synthesis | `mimo-v2.5-tts` | The [TTS guide](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/speech-synthesis-v2.5) documents style control and streaming PCM16. Audition voices separately for Columbina's unhurried, curious, playful range. |
| Voice design | `mimo-v2.5-tts-voicedesign` | Evaluate a text-designed timbre if preset voices are unsuitable. No original character voice or perceptual match is established. |

Verify whether usable timing or phoneme information is available before choosing a lip-sync technique. Streaming audio chunks alone do not establish viseme timing; presentation must follow actual audio playback. Interruption must cancel generation, queued audio, speaking state, and obsolete action cues together. Begin with text, then explicit recorded input, basic playback, and deterministic cancellation before automatic turn-taking.

## Data and credentials

The [MiMo privacy policy](https://privacy.mi.com/XiaomiMiMoPlatform/zh_CN/), effective 2026-10-10, says supplied text is not used for training or other purposes without prior consent. It also permits retention for necessary purposes or legal obligations; this is not a zero-retention guarantee or a fixed request-log expiry. Its China storage statement applies within its stated territorial scope; confirm the policy and settings applicable to the actual account.

Bina's durable memory database remains local. Selected excerpts sent in a request still reach Xiaomi. Local deletion must stop future retrieval and invalidate pending writes, but does not itself erase previously transmitted provider-side copies. The first text trial needs no full memory database, raw room mesh, camera feed, or microphone recording. Audio and voice cloning introduce separate data and consent decisions.

For the private prototype, store the developer's own key in Keychain under the architecture's client-access conditions. Never put it in source, prompts, screenshots, or conversation messages. A distributed application requires an appropriate server-held credential or supported short-lived authorization. A gateway need not become the durable memory store.

## Evaluation and preparation

Before treating the provider choice as validated:

- Run the existing portrayal scenarios with the same profile revision on Flash and Pro, using synthetic Chinese conversations. Include a multi-turn session covering ordinary topics, playfulness, disagreement, emotional recovery, the eye covering, and unavailable sensing.
- Test confirmed recall after restart, missing memory, correction, deletion, and pending extraction during deletion. No invented shared episode or unsupported save claim should pass.
- Test interrupted streams, late chunks, malformed/truncated JSON, timeout, authentication failure, rate limiting, and provider rejection without memory corruption or obsolete actions.
- Record model ID, settings, context size, token usage, first-visible-answer latency and completion latency, including p50/p95 over repeated requests on the target network. Human review must assess persona separately from technical transport success. Voice and embodied behavior remain unassessed in text-only trials.

The user needs an API-enabled Xiaomi account, any console-required identity/payment setup, access to the candidate model, and a chosen development spending limit. Keep credentials outside this chat. The first interruptible text conversation and confirmed-memory loop have a preliminary user-reported functional pass. The [voice implementation](../voice-conversation.md) now connects `mimo-v2.5-asr` and non-streaming WAV from `mimo-v2.5-tts`, with explicit preset selection and audition. Authenticated speech access, latency, voice quality, and headset behavior still require validation. Automatic model-driven actions and voice cloning remain separate work.
