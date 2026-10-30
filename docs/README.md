# Documentation Guide

Status: relaxed stance, idle, bounded head attention, selected hair physics/collision, and preview controls are implemented. All 90 simulator tests pass. The user confirmed the earlier cuff correction on visionOS 27.2; the new hair correction awaits headset quality/performance acceptance. See the spatial prototype, secondary-motion contract, and model intake for verification evidence. Last updated: 2026-10-30.

These documents distinguish long-term design from the limited implementation already present. The spatial prototype guide records current behavior; the remaining feature designs remain proposals unless explicitly identified otherwise.

## Reading order

| Document | Purpose |
| --- | --- |
| [Product vision](product-vision.md) | Understand the companion, confirmed character direction, and first complete experience. |
| [Spatial prototype](spatial-prototype.md) | Run the first D1 experiment and record actual device results. |
| [Head attention](head-attention.md) | Understand bounded neck/head motion, controls, lifecycle, and validation limits. |
| [Secondary motion](secondary-motion.md) | Reproduce selected hair physics and review collision scope, controls, native cloth options, and verification. |
| [Columbina character profile](characters/columbina.md) | Review the adaptation of the supplied identity and personality files. |
| [Columbina evaluations](characters/columbina-evaluation.md) | Assess personality fidelity through observable scenarios. |
| [Platform capabilities](platform-capabilities.md) | Distinguish available sensing from approval-dependent or unsupported assumptions. |
| [Character assets](character-assets.md) | Evaluate a Columbina model and prepare a usable character asset. |
| [Columbina model intake](characters/columbina-model.md) | Reproduce local model/pose preparation and understand source and redistribution boundaries. |
| [Memory and emotion](memory-and-emotion.md) | Define what the character remembers and how personality and emotion remain coherent. |
| [Architecture](architecture.md) | Follow information from observation through behavior to visible and audible results. |
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
