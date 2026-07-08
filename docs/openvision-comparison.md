# OpenVision comparison notes

Source: https://github.com/rayl15/OpenVision — open-source iOS app connecting Meta
Ray-Ban glasses to AI (MLX on-device models, Apple Intelligence, OpenAI, Gemini
Live, OpenClaw backends; Kokoro on-device TTS; agentic web search; face recognition).
Same problem space as Lanterna (glasses + AI assistant), evaluated 2026-07-08 for
anything worth porting.

## Already covered by Lanterna

No value in porting these — Lanterna has equivalents:
- Gemini Live backend (`Lanterna/Gemini/GeminiLiveService.swift`, `GeminiSessionViewModel.swift`)
- Agentic tool-calling backend (`Lanterna/OpenClaw/` + `Lanterna/Hermes/HermesBridge.swift`)
- WebRTC glasses video streaming, reconnect/network handling, credential storage (`KeychainManager.swift`)

## Considered and rejected: on-device backends (MLX / Apple Intelligence)

Both were evaluated as alternative AI backends. Neither is worth building:

- **MLX (local models: Qwen 2.5, Gemma 2, SmolVLM2)** — would add ongoing
  maintenance (model download/storage/eviction, picking/updating quantized
  checkpoints) for a benefit (offline, zero API cost, device reach below iOS 26)
  that doesn't clearly apply to Lanterna's use case.
- **Apple Intelligence (Foundation Models)** — cheaper to integrate at first
  glance (OS-managed, no download, native `Tool` protocol matches
  `ToolCallRouter`/`HermesBridge`'s call-and-respond shape), but Foundation
  Models is text-in/text-out only — no live duplex audio, no native video/image
  ingestion. Lanterna's actual voice pipeline is `GeminiSessionViewModel`, which
  owns a live bidirectional WebSocket (`GeminiLiveService`) streaming mic audio
  out and synthesized speech back in real time, plus periodic video frames.
  Swapping in Foundation Models isn't a backend swap behind a shared interface —
  it requires a parallel pipeline: STT (e.g. `SFSpeechRecognizer`) → text into
  `LanguageModelSession` → TTS (`AVSpeechSynthesizer`) out. That's turn-based,
  materially worse UX than Gemini Live's low-latency streaming for hands-free
  glasses interaction, and not worth the pipeline duplication.

**Decision: dropped, not pursuing either.**

## Worth a future look (not scoped/planned yet)

Self-contained features that wouldn't require a new pipeline, only if a concrete
need comes up:
- **On-device face recognition** (Apple Vision `computeDistance`) — standalone,
  no dependency on the voice backend.
- **Agentic web search** (Tavily + DuckDuckGo fallback, query reformulation) —
  could bolt onto the existing Hermes tool-call path (`ToolCallRouter.swift`)
  as a new tool rather than a new backend.
