# 1 — Project Overview: NaviSense

> Formerly codenamed **SightBridge AI**. Built for the **Google Firebase #BuildHybridAI 2026 Hackathon**.
> **Hard deadline:** Monday, November 30, 2026 — 2:00 PM PST / 22:00 UTC / **11:00 PM WAT**.
> **Internal soft submission:** Monday, November 30, 2026 — **8:00 PM WAT** (3-hour safety buffer).

---

## 1.1 One-Line Pitch

**NaviSense is an Android app that tells blind and low-vision people what is around them by voice. It works on a $90, 3 GB RAM phone in Airplane Mode and on a flagship phone running Gemini Nano 4 alike, and the user never notices the difference.**

## 1.2 Project Summary

NaviSense turns the phone camera into a spoken spatial guide. The user taps anywhere on a full-screen gesture surface. NaviSense captures a frame and returns one calm spoken guidance response, for example: *"Caution: Chair very close ahead in center. Door on your left. Sign reads EXIT."*

A **3-Tier Hybrid Pipeline** decides where each request is reasoned:

| Stage / Tier | Where it runs | Engine | Who gets it |
|---|---|---|---|
| **Stage 0** — Pre-Perception | On-device, every frame | Google ML Kit (Object Detection + Image Labeling + Text Recognition `^1.0.3`) | **All** Android devices (`minSdk 26`) |
| **Tier 1** — Edge Reasoning | On-device NPU | Gemini Nano 4 via Firebase AI Logic `PREFER_ON_DEVICE` (`firebase-ai-ondevice:16.0.0-beta08`) | AICore-capable flagships |
| **Tier 2** — Cloud Reasoning + Voice | Google Cloud | Gemini Flash via Server Prompt Templates (`templateGenerativeModel()`) + `gemini-3.1-flash-tts-preview` | Any online device without AICore |
| **Tier 3** — Deterministic Edge Fallback | On-device CPU | ML Kit `SpatialSceneSummary` → deterministic formatter → `flutter_tts` or cached WAV | Offline / Airplane Mode / low-RAM devices |

Each answer updates a **Judge Telemetry Pill** naming the tier and `inferenceSource` that produced it, so judges can observe the hybrid routing in real time.

## 1.3 Socioeconomic Problem Statement

1. **Scale of need.** WHO estimates at least 2.2 billion people have a near or distance vision impairment. Most live in low- and middle-income countries, where preventable and unaddressed impairment is most common.
2. **The hardware gap.** Most AI assistive tools assume a flagship phone with an NPU, 8–12 GB RAM, and constant 5G. Users in emerging markets more often rely on **Android Go** devices such as a **3 GB RAM Xiaomi Redmi A3**: no AICore, no NPU, an aggressive low-memory killer, and patchy 2G/3G data.
3. **The bandwidth and cost gap.** Mobile data is expensive relative to income. Streaming video to the cloud drains data bundles rapidly. NaviSense keeps perception local via Google ML Kit (<50 ms, <50 MB RAM) and sends only *one compressed snapshot per user tap* (≤ 768 px JPEG, quality 70) to the cloud, and only when on-device Gemini Nano 4 is unavailable.
4. **The safety gap.** Cloud-only assistants **go silent** when the network drops: inside tunnels, markets, or elevators. For a blind pedestrian, silence near an obstacle is a safety failure. NaviSense **never goes silent**: Tier 3 always responds deterministically from ML Kit in ≤ 300 ms.
5. **The dignity gap.** NaviSense is designed TalkBack-first, not retrofitted for sighted users. The entire screen is a 72dp+ gesture target, each tier emits a distinct haptic count, and every state change is announced.

## 1.4 #BuildHybridAI 2026 Rules & Compliance Gates

> Always re-verify against the official hackathon rules page before submission. The gates below are our internal compliance checklist.

| # | Gate | How NaviSense satisfies it | Owner unit |
|---|---|---|---|
| G1 | Uses **Firebase AI Logic** in a **hybrid** (on-device + cloud) architecture | `firebase-ai` + `firebase-ai-ondevice:16.0.0-beta08` with `InferenceMode.PREFER_ON_DEVICE`; cloud via `templateGenerativeModel()` | Units 6, 7, 9 |
| G2 | Public source repository | Public GitHub repo, `main` branch, tagged `v1.0.0-hackathon` | Unit 10 |
| G3 | **OSI open-source license detectable by GitHub** | Apache License 2.0 full text in root `LICENSE` (GitHub "About" panel detects `Apache-2.0`) | Unit 1 |
| G4 | No secrets in repo | `.gitignore` excludes `lib/firebase_options.dart`, `android/app/google-services.json`, `secrets.json`; `secrets.example.json` committed | Unit 1 |
| G5 | Security best practice | Firebase App Check: `AndroidProvider.playIntegrity` (release) / `AndroidProvider.debug` (debug) via `--dart-define-from-file=secrets.json` | Unit 2 |
| G6 | Demo video ≤ 3:00, publicly viewable | YouTube unlisted/public, blueprint in §1.7 | Unit 10 |
| G7 | Judges can run & verify it | `README.md` "For Judges" section: safelisted debug token, `--dart-define-from-file=secrets.json`, signed release APK in GitHub Releases | Unit 10 |
| G8 | Submitted before deadline | Soft submit 8:00 PM WAT; hard stop 11:00 PM WAT, Nov 30 | Tracker |
| G9 | Platform scope | **Android mobile only**. Zero Web targets or web dependencies | All units |

## 1.5 Judging Criteria (4 × Equal Weight, 25% each)

### A. Technological Implementation (25%)
- Real three-tier hybrid routing reading `InferenceSource.ON_DEVICE` vs `IN_CLOUD` from the native SDK.
- Stage 0 ML Kit pre-perception with spatial math (direction from bounding-box X-center, distance from bounding-box area ratio).
- Raw audio engineering: 44-byte little-endian RIFF/WAV header around 24 kHz, 16-bit mono PCM from `gemini-3.1-flash-tts-preview`, with atomic SHA-256 content-addressed caching on `dart:io`.
- Zero-trust security: mandatory App Check, zero client-side API keys, and real-time Remote Config prompt governance via `onConfigUpdated`.
- Memory discipline: <150 MB TOTAL PSS on a 3 GB Redmi A3 via NV21 throttling, native JPEG downscaling, and deterministic buffer disposal.

### B. Design & Coherent UX (25%)
- TalkBack-first: full-screen gesture surface (tap = describe, long-press = read text, double-tap = repeat, custom actions).
- High-contrast Deep Navy (`#141B41`) and Cream (`#F7F5F0`) palette with verified AA/AAA text contrast.
- Distinct `HapticFeedback` patterns per tier so the user feels edge vs. cloud execution.
- Non-blocking AICore model-download banner so the app works from second zero.

### C. Potential Impact (25%)
- Built specifically for emerging-market Android Go hardware (3 GB RAM Redmi A3) as well as AICore flagships.
- Operates safely with **zero connectivity** (Airplane Mode).
- $0 marginal token cost on Tier 1 and Tier 3; minimal single-snapshot bandwidth on Tier 2.

### D. Quality of the Idea (25%)
- "Graceful intelligence degradation": identical interaction model across a wide hardware and connectivity spectrum.
- Hybrid AI framed as a **pedestrian safety guarantee** (never silent), not merely a cost optimization.

## 1.6 Judging Panel Alignment (Firebase AI Logic & Flutter Lenses)

### 1. Product, Security & Cost Optimization Lens
- **Core Priorities & How NaviSense Satisfies Them:**
  - *Eliminating client-side API keys via mandatory Firebase App Check:* Zero API keys in Dart/Kotlin; App Check enforced (`AndroidProvider.playIntegrity` in release, `AndroidProvider.debug` + `--dart-define-from-file=secrets.json` in debug) on both Firebase AI Logic and Remote Config.
  - *Eliminating hardcoded prompt/model updates via Server Prompt Templates (Dotprompt) + Remote Config:* Tier 2 uses `templateGenerativeModel()` with `navisense_nav_prompt_v1` / `v2` governed live by `FirebaseRemoteConfig.instance.onConfigUpdated` (`active_prompt_template`).
  - *Cost optimization via `PREFER_ON_DEVICE` and spend caps:* Stage 0 ML Kit filters frames locally, Tier 1 routes through `InferenceMode.PREFER_ON_DEVICE` at $0 token cost, and Tier 2 only sends one ≤ 768 px snapshot per user tap with strict 1500 ms timeouts and SHA-256 WAV audio caching to avoid repeat TTS calls.
  - *Hands-free accessibility using `gemini-3.1-flash-tts-preview`:* Full-screen blind-first gesture surface paired with natural, calm voice synthesis from `gemini-3.1-flash-tts-preview` (`voiceName: 'Kore'`), failing over cleanly to `flutter_tts` offline.

### 2. Hybrid Architecture & Flutter Engineering Lens
- **Core Priorities & How NaviSense Satisfies Them:**
  - *Intelligent edge-to-cloud orchestration:* Unified 3-tier pipeline combining ML Kit Stage 0 (`SpatialSceneSummary`) → Tier 1 Gemini Nano 4 (`OnDeviceExtension`) → Tier 2 Cloud Templates + TTS → Tier 3 deterministic edge fallback (`flutter_tts` / cached WAV).
  - *Clean reactive state management (Riverpod) during network drops:* `AiOrchestrator` (`AsyncNotifier`), `TelemetryNotifier` (`Notifier`), and `NanoStatusNotifier` isolate async lifecycles, enforce strict 1500 ms cloud timeouts, discard stale requests via `requestId`, and never throw unhandled errors to the UI.
  - *Non-blocking model initialization/download states:* `NanoDownloadBanner` listens to the `EventChannel` (`navisense/gemini_nano/download`) only when `getStatus() == DOWNLOADABLE | DOWNLOADING`, throttling TalkBack progress announcements to 25% increments while keeping Tier 2/3 immediately usable.
  - *Exposing `inferenceSource` (`ON_DEVICE` vs `IN_CLOUD`) telemetry in the UI:* `GeminiNanoBridge.kt` reads `response.inferenceSource` natively and surfaces it in the color-coded, haptic-paired **Judge Telemetry Pill** (`ON_DEVICE • Gemini Nano 4 • 0ms • $0` vs `IN_CLOUD • Gemini Flash TTS` vs `ON_DEVICE • ML Kit Edge Fallback • 0ms • $0`).

| Evaluation lens | What we prove | Where in the 3-min video |
|---|---|---|
| Zero-trust & Server Prompt Templates | App Check enforced, zero keys in repo, live Remote Config swap `v1` → `v2` without APK rebuild | 2:05–2:45 |
| Cost optimization & Gemini TTS | `PREFER_ON_DEVICE` $0 edge inference + `gemini-3.1-flash-tts-preview` audio cached via SHA-256 | 0:35–1:35 |
| Edge-to-cloud orchestration & Riverpod resilience | Seamless failover on a 3 GB Redmi A3 into Airplane Mode with zero silence or crash | 1:20–2:05 |
| Non-blocking Nano lifecycle & `inferenceSource` UI | `OnDeviceExtension` status check + live Telemetry Pill switching Emerald / Royal Blue / Antique Gold | 0:35–1:20, 2:45–2:58 |

## 1.7 Three-Minute Demo Video Blueprint (180 s, hard cap)

**Setup:** Two phones on tripods, screens mirrored with `scrcpy` into a split-screen recording:
- **Phone A (Flagship):** AICore-capable Android phone with Gemini Nano 4 downloaded.
- **Phone B (Low-end):** Xiaomi Redmi A3, 3 GB RAM, Android Go.
- **Scene:** Hallway with a chair in the center (~0.8 m away), a door on the left, and an `"EXIT"` sign.
- **Laptop:** Firebase Console → Remote Config tab, pre-loaded.
- **Audio:** Phone speakers captured by a lavalier mic; TalkBack ON on both phones.

| Time | Visual | Audio / Narration | Proof point |
|---|---|---|---|
| 0:00–0:08 | Black screen → NaviSense logo in Antique Gold on Deep Navy | "2.2 billion people live with vision impairment. Most of them don't own a flagship phone." | Hook |
| 0:08–0:20 | Close-up of Redmi A3 box: "3GB RAM" | "NaviSense is a hybrid AI guide built to run on the phone they *do* own." | Problem |
| 0:20–0:35 | Architecture diagram: Stage 0 ML Kit → Tier 1 Nano → Tier 2 Cloud → Tier 3 Fallback | "Every frame is pre-perceived locally by Google ML Kit. Then Firebase AI Logic decides where to reason." | Architecture |
| 0:35–0:55 | **Phone A** tapped. Pill turns Emerald (`#10B981`): `ON_DEVICE • Gemini Nano 4 • 0ms • $0`. Double-pulse haptic. | Phone speaks: "There's a chair directly in front of you, very close. A door is on your left, and an exit sign above it." | Tier 1 |
| 0:55–1:20 | Overlay: `OnDeviceConfig(mode = InferenceMode.PREFER_ON_DEVICE)` + log line `inferenceSource=ON_DEVICE` | "That ran on the Gemini Nano 4 NPU via `OnDeviceExtension`. Zero network latency, zero token cost." | Tech depth |
| 1:20–1:35 | **Phone B** (online) tapped. Pill turns Royal Blue (`#3B82F6`): `IN_CLOUD • Gemini Flash TTS`. Single heavy haptic. | Natural `gemini-3.1-flash-tts-preview` voice (`Kore`) speaks guidance | Tier 2 |
| 1:35–1:45 | Hand swipes down quick settings on Phone B → **Airplane Mode ON** (clearly visible) | "Now the real-world test. No AICore. No network." | Offline setup |
| 1:45–2:05 | **Phone B** tapped. Pill turns Antique Gold (`#B18A41`): `ON_DEVICE • ML Kit Edge Fallback • 0ms • $0`. Triple short haptic. | Local TTS: "Caution: Chair very close ahead in center. Door on your left. Sign reads EXIT." | **Tier 3, never silent** |
| 2:05–2:20 | Laptop: Remote Config → `active_prompt_template` changed from `navisense_nav_prompt_v1` to `navisense_nav_prompt_v2` → **Publish** | "Prompts are governed server-side with Dotprompt and Remote Config. I'm switching templates live." | Governance |
| 2:20–2:35 | Phone B Airplane Mode OFF → tap. TalkBack announces: "Guidance style updated." Response uses v2 clock-face style ("Chair at 12 o'clock, one step.") | "No APK rebuild, no redeploy. Real-time `onConfigUpdated` stream." | Hot-swap |
| 2:35–2:45 | README "For Judges" + App Check console showing verified requests + Apache-2.0 GitHub badge | "App Check with Play Integrity. Zero API keys in the repo. Apache 2.0." | Security |
| 2:45–2:58 | Both phones side by side, pills in all three colors | "Flagship or $90 phone. Online or offline. NaviSense never goes silent." | Impact |
| 2:58–3:00 | Logo + public GitHub repo URL | — | CTA |

**Recording rules:**
- Record each segment 3× and keep the best take. Never speed up AI response footage; label any cut.
- Burn in captions for every spoken phrase.
- Final export: 1080p, H.264, ≤ 2:59.

## 1.8 Target Performance Metrics

| Metric | Target | Measured on |
|---|---|---|
| Tap → first audio (Tier 3) | ≤ 300 ms | Redmi A3, Airplane Mode |
| Tap → first audio (Tier 1) | ≤ 1500 ms | Flagship w/ Gemini Nano 4 |
| Tap → first audio (Tier 2) | ≤ 2500 ms (cache miss), ≤ 200 ms (cache hit) | Redmi A3 on 4G/Wi-Fi |
| Peak PSS | < 150 MB | Redmi A3 (`adb shell dumpsys meminfo com.navisense.app`) |
| Crash-free sessions in 30-min soak | 100% | Redmi A3 |
| Silent failures | 0 | All tiers |
