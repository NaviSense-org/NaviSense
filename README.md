# NaviSense

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**NaviSense is an Android app that tells blind and low-vision people what is around them by voice. It works on a $90, 3 GB RAM phone in Airplane Mode and on a flagship phone running Gemini Nano 4 alike, and the user never notices the difference.**

Built for the **Google Firebase #BuildHybridAI 2026 Hackathon**.

---

## Architecture

NaviSense uses a **3-Tier Hybrid AI Pipeline** backed by local Google ML Kit Stage 0 pre-perception so every tap delivers calm spoken spatial guidance and never goes silent:

```
┌───────────────────────────── Flutter (Dart) ─────────────────────────────┐
│ GestureSurface ─▶ CameraService ─▶ MlKitPerceptionService ─▶ SpatialSceneSummary
│        │                                                     │
│        └─tap─▶ JPEG snapshot ─▶ AiOrchestrator ◀──────────────┘
│                                   │      │        │
│                 ┌─────────────────┘      │        └───────────────┐
│                 ▼                        ▼                        ▼
│        NanoBridge (MethodChannel)  CloudReasoningService   DeterministicSpatialFormatter
│                 │                  + CloudTtsService               │
│                 │                  + WavCache (sha256)             ▼
│                 │                        │                 LocalTtsService / WavCache
│                 ▼                        ▼                        │
│           TelemetryNotifier ◀────────────┴────────────────────────┘
└─────────────────┬─────────────────────────────────────────────────────────┘
                  │ MethodChannel "navisense/gemini_nano"
                  │ EventChannel  "navisense/gemini_nano/download"
┌─────────────────▼──────────── Android (Kotlin) ──────────────────────────┐
│ MainActivity ─▶ GeminiNanoBridge ─▶ firebase-ai GenerativeModel           │
│                                     + OnDeviceConfig(PREFER_ON_DEVICE)    │
│                                     + GenerativeModel.OnDeviceExtension   │
│                                     (firebase-ai-ondevice:16.0.0-beta08)  │
│                                     ─▶ AICore ─▶ Gemini Nano 4 (NPU)      │
└──────────────────────────────────────────────────────────────────────────┘
```

| Stage / Tier | Where it runs | Engine | Who gets it | Telemetry Pill |
|---|---|---|---|---|
| **Stage 0** — Pre-Perception | On-device | Google ML Kit (Object Detection + Image Labeling + Text Recognition `^1.0.3`) | **All** Android devices (`minSdk 26`) | — |
| **Tier 1** — Edge Reasoning | On-device NPU | Gemini Nano 4 via Firebase AI Logic `PREFER_ON_DEVICE` (`firebase-ai-ondevice:16.0.0-beta08`) | AICore-capable flagships | `ON_DEVICE • Gemini Nano 4 • 0ms • $0` |
| **Tier 2** — Cloud Reasoning + Voice | Google Cloud | Gemini Flash via Server Prompt Templates (`templateGenerativeModel()`) + `gemini-3.1-flash-tts-preview` | Online devices without AICore | `IN_CLOUD • Gemini Flash TTS` (or `• local voice` on TTS failover) |
| **Tier 3** — Deterministic Edge Fallback | On-device CPU | ML Kit `SpatialSceneSummary` -> deterministic formatter -> `flutter_tts` or SHA-256 cached WAV | Offline / Airplane Mode / low-RAM devices | `ON_DEVICE • ML Kit Edge Fallback • 0ms • $0` |

---

## For Judges

### 1. Release APK (GitHub Releases)

Install the signed release APK from **GitHub Releases** (`v1.0.0-hackathon`) for immediate testing of Tier 2 and Tier 3 (and Tier 1 on AICore flagships).

> **Play Integrity note:** Play Integrity attestation in release builds may require installation from a Google Play-trusted channel. If Play Integrity rejects sideloaded requests on your test device, run the debug build below using a safelisted debug token.

### 2. Debug Build Path (Verified App Check Debug Provider)

> This must be a **debug** build: the App Check debug provider (`AndroidDebugProvider`) is active only when `kDebugMode` is true; release builds always enforce `AndroidPlayIntegrityProvider`.

1. Clone the repository:
   ```sh
   git clone https://github.com/okikday/NaviSense.git
   cd NaviSense
   ```
2. Place the `android/app/google-services.json` and `lib/firebase_options.dart` provided privately by the team (or generate your own with `flutterfire configure --project=<your-project> --platforms=android --android-package-name=com.navisense.app`).
   - In your own Firebase project, enable **Firebase AI Logic** (Gemini Developer API), **Firebase App Check**, and **Remote Config**, and create the two Server Prompt Templates `navisense_nav_prompt_v1` and `navisense_nav_prompt_v2` under **AI Logic -> Prompt templates** (definitions in [`context/2-architecture.md`](context/2-architecture.md#L387-L430)).
3. Copy the debug token template and insert your safelisted App Check debug token:
   ```sh
   cp secrets.example.json secrets.json
   ```
   Edit `secrets.json` and paste the safelisted token provided by the team (or launch once, search logcat for `Enter this debug secret into the allow list`, add it in **Firebase Console -> App Check -> Apps -> Manage debug tokens**, and paste it into `secrets.json`).
4. Run on an Android device (`minSdk 26+`):
   ```sh
   flutter run --dart-define-from-file=secrets.json
   ```

### 3. How to Trigger Each Tier

- **Tier 1 (`ON_DEVICE • Gemini Nano 4 • 0ms • $0`, 2x medium haptic):** Run on an AICore-capable Android flagship with Gemini Nano 4 downloaded (tap **Download** in the non-blocking top banner if status is `DOWNLOADABLE`). Tap anywhere on the screen.
- **Tier 2 (`IN_CLOUD • Gemini Flash TTS`, 1x heavy haptic):** Run online on any Android phone (`minSdk 26+`, e.g., 3 GB RAM Redmi A3) without AICore. Tap anywhere; cloud Server Prompt Template reasoning + `gemini-3.1-flash-tts-preview` audio plays and caches atomically to SHA-256 WAV storage.
- **Tier 3 (`ON_DEVICE • ML Kit Edge Fallback • 0ms • $0`, 3x light haptic):** Turn on **Airplane Mode** on any phone and tap anywhere. Deterministic ML Kit spatial guidance speaks immediately (`<= 300 ms` target) and replays cached `Kore` WAV audio when identical phrases hit the SHA-256 disk cache.

### 4. How to Watch the Live Remote Config Hot-Swap

1. Open **Firebase Console -> Remote Config** for your Firebase project (e.g. `navisense-23425`).
2. Change `active_prompt_template` from `navisense_nav_prompt_v1` to `navisense_nav_prompt_v2` and click **Publish changes**.
3. On a running online phone (no restart or APK rebuild), `FirebaseRemoteConfig.onConfigUpdated` logs `navisense.rc template=navisense_nav_prompt_v2` and announces `"Guidance style updated"`.
4. Tap anywhere: guidance immediately switches to v2 clock-face phrasing (`"Chair at 12 o'clock, one step"`).

---

## Security & Privacy Model

- **Zero API keys in repository:** `android/app/google-services.json`, `lib/firebase_options.dart`, `secrets.json`, `*.jks`, and `android/key.properties` are gitignored. All Gemini calls flow through Firebase AI Logic protected by App Check.
- **Transient snapshot discipline:** Frames stay in memory during Stage 0 NV21 perception (`<= 1.4 fps`), snapshots are downscaled natively in Kotlin (`<= 768 px`, JPEG quality 70) and deleted in `finally`, and only normalized guidance WAVs are cached on disk (`<= 20 MB`, `<= 200` files LRU).
- **Zero telemetry PII / zero analytics SDKs.**

## Memory & Performance Budget (3 GB RAM Target)

- Stream resolution locked to `ResolutionPreset.medium` (`ImageFormatGroup.nv21`, `enableAudio: false`).
- 700 ms frame throttle + busy drop guard; sequential ML Kit detector execution to avoid native heap spikes.
- Native Kotlin JPEG downscaling via `BitmapFactory.Options.inSampleSize` + `createScaledBitmap` with deterministic `bitmap.recycle()` in `finally`.
- Single `AudioPlayer` (`PlayerMode.mediaPlayer`) streaming cached WAVs via `DeviceFileSource`.

## Verification

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=secrets.example.json
```

## License

Copyright 2026 NaviSense Contributors

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full license text.

## Acknowledgements

- [Google Firebase AI Logic](https://firebase.google.com/docs/ai-logic) & `firebase-ai-ondevice`
- [Google ML Kit](https://developers.google.com/ml-kit)
- [Flutter](https://flutter.dev) & [Riverpod](https://riverpod.dev)
