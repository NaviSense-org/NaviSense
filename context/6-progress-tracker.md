# 6 — Progress Tracker

**Legend:** `[ ] TODO` · `[~] IN_PROGRESS` · `[x] DONE`
**Timezone:** all times WAT (UTC+1). PST = WAT − 9h.

| Milestone | Date / Time (WAT) |
|---|---|
| Day 1 kickoff | Tue Nov 17, 2026 |
| Feature freeze | Fri Nov 27, 2026, 11:59 PM |
| Demo video locked | Sun Nov 29, 2026, 9:00 PM |
| **Soft submission (internal)** | **Mon Nov 30, 2026, 8:00 PM** |
| **Hard deadline** | **Mon Nov 30, 2026, 11:00 PM** (= 2:00 PM PST) |

---

## Phase 0 — Context & Setup (Nov 17)

- [x] DONE — Write `context/` files 1–7
- [~] IN_PROGRESS — Created Firebase project `navisense-hybrid` (`1043981425502`); enable Firebase AI Logic (Gemini Developer API) in Console
- [~] IN_PROGRESS — Registered Android app `com.navisense.app` (`1:1043981425502:android:6e652e60e9b1b8d5db4dcf`) + debug SHA-256; upload SHA-256 pending release keystore (Unit 10)
- [x] DONE — Create public GitHub repo `navisense` (empty, Apache-2.0 selected or LICENSE added in Unit 1)
- [ ] TODO — Acquire/charge test devices: AICore flagship + Xiaomi Redmi A3 (3 GB)

## Phase 1 — Foundation (Nov 17–18)

### Unit 1 — Scaffold, dependencies, zero-secret repo
- [x] DONE — `flutter create --platforms=android --org com.navisense navisense`
- [x] DONE — `pubspec.yaml` deps per §2.1; exact pins committed
- [x] DONE — `android/app/build.gradle.kts` minSdk 26 / compile 36 / target 36, BoM 35.2.0, ondevice beta08
- [x] DONE — `.gitignore` zero-secret block; `secrets.example.json`
- [x] DONE — Apache 2.0 `LICENSE`; GitHub "About" shows Apache-2.0
- [x] DONE — Debug APK builds

### Unit 2 — Firebase bootstrap, App Check, Remote Config
- [x] DONE — `flutterfire configure` (output gitignored)
- [x] DONE — App Check debug/playIntegrity switch + `--dart-define-from-file`
- [x] DONE — Remote Config defaults + `onConfigUpdated` listener + whitelist
- [x] DONE — Unit tests for template whitelist/fallback

## Phase 2 — Perception (Nov 19–20)

### Unit 3 — Camera service & lifecycle
- [x] DONE — NV21 stream, 700 ms throttle, busy flag
- [x] DONE — Lifecycle pause/resume, snapshot capture with stream pause
- [x] DONE — Native `compressJpeg` + `getDeviceMemoryClass`
- [ ] TODO — 10-min soak on Redmi A3 < 150 MB PSS (requires physical device)

### Unit 4 — ML Kit `SpatialSceneSummary`
- [x] DONE — Spatial math + tests (direction/distance boundaries)
- [x] DONE — Three detectors, sequential, label fusion, OCR filtering
- [x] DONE — `toPromptString()` golden test
- [ ] TODO — Stage 0 ≤ 50 ms median on Redmi A3 (logged) (requires physical device)

## Phase 3 — Edge Fallback & Voice (Nov 21–22)

### Unit 5 — Deterministic formatter + local TTS
- [x] DONE — Formatter golden tests incl. "Caution: Chair very close ahead in center. Door on your left. Sign reads EXIT."
- [x] DONE — `LocalTtsService` (awaitSpeakCompletion, 0.45, 1.0), engine/language detection
- [ ] TODO — Airplane Mode tap → speech ≤ 300 ms on Redmi A3 (requires physical device)

## Phase 4 — Hybrid AI (Nov 23–25)

### Unit 6 — Gemini Nano 4 native bridge
- [x] DONE — `GeminiNanoBridge.kt` getStatus/startDownload/generate + EventChannel
- [x] DONE — API names verified vs firebase-ai 18.2.0 / ondevice beta08 (record CONTRACT CHANGE if needed)
- [x] DONE — Dart `NanoBridge` typed client + mocked tests
- [ ] TODO — Flagship returns `inferenceSource=ON_DEVICE` (requires physical AICore flagship)

### Unit 7 — Cloud reasoning via Server Prompt Templates
- [ ] TODO — Templates v1/v2 created in Firebase console (requires Firebase Console)
- [x] DONE — `CloudReasoningService` with 1500 ms timeout + failure mapping
- [ ] TODO — Live call succeeds with App Check enforced (requires Firebase Console + physical device)

### Unit 8 — Cloud TTS, PCM→WAV, SHA-256 cache
- [x] DONE — `pcmToWav` + header byte tests
- [x] DONE — `WavCache` atomic write, LRU 20 MB/200 files
- [x] DONE — `CloudTtsService` + `VoicePlayer` (BytesSource/DeviceFileSource)

### Unit 9 — AI Orchestrator & telemetry
- [x] DONE — Tier router + state machine + stale-result guard
- [x] DONE — `TelemetryNotifier` with exact pill labels
- [x] DONE — Routing tests (all 8 transitions in §2.7)

## Phase 5 — UX, Hardening, Submission (Nov 26–30)

### Unit 10 — TalkBack UI, haptics, release, README, demo
- [x] DONE — HomeScreen, GestureSurface, pill, banner, bottom controls, settings
- [x] DONE — Haptic patterns per tier; semantics + 72dp tests
- [ ] TODO — Manual TalkBack pass on both devices
- [ ] TODO — Release APK (Play Integrity) uploaded to GitHub Releases
- [x] DONE — README "For Judges" section complete
- [ ] TODO — App Check enforcement ON for AI Logic + Remote Config

### Submission
- [ ] TODO — Nov 28: record demo takes (all 12 segments)
- [ ] TODO — Nov 29 9:00 PM: video edited, captioned, ≤ 2:59, uploaded
- [ ] TODO — Nov 30 12:00 PM: final repo audit (secret scan, LICENSE detected, tag `v1.0.0-hackathon`)
- [ ] TODO — **Nov 30 8:00 PM: soft submission complete**
- [ ] TODO — Nov 30 8:00–11:00 PM: buffer only (no code changes); confirm submission receipt

---

## Day-by-Day Plan

| Date | Focus | Units | Exit criteria |
|---|---|---|---|
| Tue Nov 17 | Context, Firebase project, repo | Phase 0, Unit 1 | Debug APK builds, LICENSE detected |
| Wed Nov 18 | Firebase bootstrap | Unit 2 | RC hot-swap logged on device |
| Thu Nov 19 | Camera | Unit 3 | Soak test passes |
| Fri Nov 20 | ML Kit | Unit 4 | Golden summary on real hallway |
| Sat Nov 21 | Formatter + local TTS | Unit 5 | Airplane Mode guidance works |
| Sun Nov 22 | Buffer / Redmi A3 tuning | — | PSS < 150 MB |
| Mon Nov 23 | Nano bridge | Unit 6 | ON_DEVICE on flagship |
| Tue Nov 24 | Cloud templates | Unit 7 | IN_CLOUD text ≤ 1500 ms |
| Wed Nov 25 | Cloud TTS + cache | Unit 8 | WAV plays, cache hit offline |
| Thu Nov 26 | Orchestrator | Unit 9 | All tiers routed on both phones |
| Fri Nov 27 | UI + TalkBack | Unit 10 | **Feature freeze 11:59 PM** |
| Sat Nov 28 | Release build, README, demo recording | Unit 10 | Release APK + raw footage |
| Sun Nov 29 | Video edit, bug fixes only | — | Video locked 9:00 PM |
| Mon Nov 30 | Audit + submit | — | **Soft submit 8:00 PM**, hard stop 11:00 PM |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| beta08 on-device API differs from docs | Medium | High | Unit 6 verification gate; Tier 2/3 work regardless |
| No AICore flagship available for demo | Low | High | Borrow/rent device by Nov 22; fallback: show Tier 1 on emulator logs + explain |
| Cloud TTS latency > 1500 ms on 4G | Medium | Medium | Cache warm-up of demo sentences; local-voice fallback keeps IN_CLOUD text |
| Redmi A3 OOM | Medium | High | §4.5 rules, daily soak test |
| Android Go lacks offline TTS voice | Medium | High | Pre-install Google TTS en-US voice; TalkBack announce fallback |
| Play Integrity fails on sideloaded APK | Medium | Medium | Judges use debug build + safelisted token (README) |

---

## Changelog

| Date (WAT) | Unit | Summary | Verification |
|---|---|---|---|
| 2026-11-17 | Phase 0 | Created context files 1–7 | n/a (docs only) |
| 2026-11-18 | Unit 1 | Scaffolded Android-only Flutter app (`com.navisense.app`), pinned `pubspec.yaml`/`pubspec.lock` deps, configured `build.gradle.kts` (`minSdk 26`, `compileSdk 36`, `targetSdk 36`, BoM `35.2.0`, `firebase-ai-ondevice:16.0.0-beta08`), `AndroidManifest.xml`, ProGuard, `analysis_options.yaml`, `.gitignore`, `README.md`, `NaviColors`, and bootstrap `main.dart` | `dart format` clean, `flutter analyze` 0 issues, `flutter test` 1/1 green, `:app:compileDebugKotlin` & debug APK built (`sdkVersion:'26'`, `targetSdkVersion:'36'`), zero-secret & web-ban checks clean |
| 2026-11-18 | Unit 2 | Created `navisense-hybrid`, registered `com.navisense.app` + debug SHA-256, ran `flutterfire configure`, added `NaviFailure`, `AppCheckBootstrap`, `RemoteConfigService`, `PromptTemplateNotifier`, and `ProviderScope` bootstrap in `main.dart`. CONTRACT CHANGE: `Firebase.initializeApp()` relies on Android `google-services.json` resources so committed code does not import gitignored `firebase_options.dart`. | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 13/13 green, debug APK built with `google-services.json` active (`-Ptarget-platform=android-arm`), zero-secret & web-ban checks clean |
| 2026-11-18 | Unit 3 | Added `Clock`, native `MainActivity.kt` (`compressJpeg`, `getDeviceMemoryClass`, `openAppSettings`), `CameraService` + `FrameThrottler`, `CameraControllerNotifier` lifecycle observer, `CameraPreviewLayer`, and `throttle_test.dart` | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 18/18 green, `:app:compileDebugKotlin -Ptarget-platform=android-arm` `BUILD SUCCESSFUL` |
| 2026-11-18 | Unit 4 | Added `SpatialSceneSummary`/`SpatialEntity`, `spatial_math.dart`, sequential `MlKitPerceptionService` (label fusion, `<0.65` filtering, OCR area/length filtering, 5-entity cap), `perceptionProvider`, and spatial/serialization tests | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 32/32 green, `CameraImage? _` grep clean |
| 2026-11-18 | Unit 5 | Added `DeterministicSpatialFormatter`, `LocalTtsService`, `ConnectivityProbe` (300 ms DNS probe, 5 s cache), and golden/unit tests | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 41/41 green |
| 2026-11-18 | Unit 6 | Added `GeminiNanoBridge.kt` (`@OptIn(PublicPreviewAPI::class)`), `MainActivity.kt` EventChannel + MethodChannel wiring, Dart `NanoBridge` + `NanoStatusNotifier` + `nanoDownloadProgressProvider`, and mocked channel tests. CONTRACT CHANGE: verified `com.google.firebase.ai.*` package paths, nullable `onDeviceExtension?`, and sealed `DownloadStatus` subtypes. | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 48/48 green, `:app:compileDebugKotlin -Ptarget-platform=android-arm` `BUILD SUCCESSFUL`, `git grep FirebaseAIOnDevice` clean |
| 2026-11-18 | Unit 7 | Added `GuidanceTier`/`GuidanceResult`/`CloudReasoningResult`, `CloudReasoningService` (`templateGenerativeModel()`, 1500 ms timeout, `NaviFailure` mapping), and `cloud_reasoning_service_test.dart`. CONTRACT CHANGE: `FirebaseAI.googleAI()` resolves `FirebaseAppCheck` from `FirebaseApp` automatically. | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 55/55 green |
| 2026-11-18 | Unit 8 | Added `pcmToWav` RIFF/WAVE codec, `WavCache` (SHA-256 key normalization, atomic `.tmp`→`.wav`, 20 MB/200-file LRU eviction), `CloudTtsService` (`gemini-3.1-flash-tts-preview`), `VoicePlayer` (single `AudioPlayer` + TTS arbitration), and WAV codec/cache tests | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 61/61 green |
| 2026-11-18 | Unit 9 | Added `AiOrchestrator` (3-tier failover router, `describe`/`readText`/`repeat`/`stop`, `_requestId` stale guard, Stage 0 freshness check, TalkBack fallback on total voice failure), `TelemetryNotifier` with exact §3.7 pill labels, and routing/telemetry tests | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 75/75 green |
| 2026-11-19 | Unit 10 | Added `NaviTheme`, `Result`, `Haptics` (tier-distinct vibration patterns), `TelemetryPill`, `NanoDownloadBanner`, `GestureSurface`, `BottomControls`, `HomeScreen` (with camera permission overlay + first-launch TalkBack prompt + 5 s heartbeat), `SettingsScreen`, `NaviSenseApp` (`app.dart` + `main.dart` bootstrap), optional `android/key.properties` release signing DSL, judge `README.md`, and TalkBack semantics / 72dp touch-target / contrast tests | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 79/79 green, `:app:compileDebugKotlin -Ptarget-platform=android-arm` `BUILD SUCCESSFUL`, debug APK built (`--target-platform android-arm`), zero-secret & web-ban checks clean |
| 2026-11-19 | Unit 10 Polish | Fixed `CameraPermissionRecoveryOverlay` TalkBack semantics & cover aspect-ratio preview + gradient scrim, fixed 72dp `SettingsScreen` `AppBar`, removed verbose subtitles in favor of grouped `navySurface` cards/hairline dividers, added visual `Analyzing…` pill & download progress bar, eliminated 200% font-scale overflow on `HomeScreen`, and added Settings 72dp + permission recovery + 200% scale tests | `dart format` clean (0 changed), `flutter analyze` 0 issues, `flutter test` 82/82 green, `:app:compileDebugKotlin -Ptarget-platform=android-arm` `BUILD SUCCESSFUL`, debug APK built (`--target-platform android-arm`), zero-secret & web-ban checks clean |
