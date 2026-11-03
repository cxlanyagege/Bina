# Documentation Guide

Status: spatial presence, calibrated foot forms, stance/idle, attention, selected hair physics, facial previews, and MiMo text dialogue with confirmed local memory are implemented and have preliminary user-reported passes. Push-to-talk speech, review, preset synthesis, playback, and coordinated activity cues are implemented with separate headset acceptance outstanding. The toolchain and Simulator use 27.2, matching the user-reported headset version. Structured persona evaluation and measured performance remain open. Last updated: 2026-11-02.

These documents distinguish long-term design from the limited implementation already present. The spatial prototype guide records current behavior; the remaining feature designs remain proposals unless explicitly identified otherwise.

## Reading order

| Document | Purpose |
| --- | --- |
| [Product vision](product-vision.md) | Understand the companion, confirmed character direction, and first complete experience. |
| [Spatial prototype](spatial-prototype.md) | Run the first D1 experiment and record actual device results. |
| [Floor placement](floor-placement.md) | Understand live classified floors, preview/confirmation, sole contact, fallback, persistence compatibility, and headset checks. |
| [Footwear and sole contact](footwear.md) | Review water-heel/barefoot selection, fixed foot calibration, mesh ownership, and matching contact correction. |
| [Footwear mesh investigation](footwear-mesh-investigation.md) | Review the historical pass, renderer failure isolation, native-import correction, and verification evidence. |
| [Head attention](head-attention.md) | Understand bounded neck/head motion, controls, lifecycle, and validation limits. |
| [Secondary motion](secondary-motion.md) | Reproduce selected hair physics and review collision scope, controls, native cloth options, and verification. |
| [Facial presentation](facial-presentation.md) | Reproduce facial target repair, covered/closed and uncovered/open states, blinking, previews, and lifecycle checks. |
| [Columbina character profile](characters/columbina.md) | Review the adaptation of the supplied identity and personality files. |
| [Columbina evaluations](characters/columbina-evaluation.md) | Assess personality fidelity through observable scenarios. |
| [Platform capabilities](platform-capabilities.md) | Distinguish available sensing from approval-dependent or unsupported assumptions. |
| [Character assets](character-assets.md) | Evaluate a Columbina model and prepare a usable character asset. |
| [Columbina model intake](characters/columbina-model.md) | Reproduce local model/pose preparation and understand source and redistribution boundaries. |
| [Memory and emotion](memory-and-emotion.md) | Define what the character remembers and how personality and emotion remain coherent. |
| [Text conversation and local memory](text-conversation.md) | Configure MiMo, run the first text/memory loop, and understand cancellation, data handling, and verification. |
| [Push-to-talk conversation](voice-conversation.md) | Record and review speech, audition presets, play replies, interrupt safely, and run the headset acceptance checklist. |
| [Architecture](architecture.md) | Follow information from observation through behavior to visible and audible results. |
| [Xiaomi MiMo evaluation](providers/xiaomi-mimo.md) | Review the intended cloud provider, model candidates, API constraints, cost, data handling, and validation plan. |
| [Milestones](milestones.md) | Choose the next experiment and determine whether its result is sufficient. |

## Decision language

- **Confirmed**: a product direction explicitly accepted by the user.
- **Proposed**: a recommended design that still needs implementation evidence or product refinement.
- **Open**: information or a choice still needed for dependent work.
- **Verified platform fact**: behavior supported by a linked official source, with a review date.
- **Implemented**: behavior present in code. Record build, automated-test, and device evidence separately; implementation alone does not establish device acceptance.

An available API is not evidence that Bina has implemented a feature. A successful experiment is not a guarantee of performance in every room, network, or device condition.

## Document ownership

Product intent belongs in the product vision. Character-specific portrayal and its source record belong under `characters/`. Apple API constraints belong in platform capabilities. Asset requirements belong in character assets. Memory and emotional behavior belong in their dedicated design. Architecture describes the contracts between these concerns. Milestones own sequencing and acceptance evidence.

Link to the authoritative document instead of copying a rule into several places. Update affected documents when a decision changes. Record the reason, date, and practical consequence of substantial architecture or platform decisions in the relevant document; create separate decision records only when their history becomes useful.

All developer-facing prose is written in English. Character dialogue and user-visible application language can be selected independently.
