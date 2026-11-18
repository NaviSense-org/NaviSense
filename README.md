# NaviSense

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**NaviSense** is an Android-only, TalkBack-first hybrid AI spatial guide for blind and low-vision pedestrians, built for the **Google Firebase #BuildHybridAI 2026 Hackathon**. It works seamlessly on both a 3 GB RAM Android Go device in Airplane Mode and an AICore flagship running Gemini Nano 4.

## 3-Tier Hybrid Pipeline

| Stage / Tier | Execution | Engine | Target Devices |
|---|---|---|---|
| **Stage 0** — Pre-Perception | On-device | Google ML Kit (Object Detection, Image Labeling, Text Recognition) | All Android devices (`minSdk 26`) |
| **Tier 1** — Edge Reasoning | On-device NPU | Gemini Nano 4 via Firebase AI Logic `PREFER_ON_DEVICE` | AICore-capable flagships |
| **Tier 2** — Cloud Reasoning + Voice | Google Cloud | Gemini Flash via Server Prompt Templates + `gemini-3.1-flash-tts-preview` | Online devices without AICore |
| **Tier 3** — Deterministic Edge Fallback | On-device CPU | ML Kit `SpatialSceneSummary` -> deterministic formatter -> `flutter_tts` / cached WAV | Offline / Airplane Mode / low-RAM devices |

## Build Prerequisites

- **Platform:** Android only (`minSdk 26`, `compileSdk 36`, `targetSdk 36`).
- **Toolchain:** Flutter `>=3.27.0` (Dart `>=3.5.0 <4.0.0`), JDK 17, Android SDK Platform 36.
- **Zero-Secret Configuration:**
  1. Copy `secrets.example.json` to `secrets.json` and fill in your safelisted Firebase App Check debug token.
  2. Provide gitignored `android/app/google-services.json` and `lib/firebase_options.dart` (generated via `flutterfire configure --platforms=android` in Unit 2).
  3. Build/run with `--dart-define-from-file=secrets.json`.

## Verification Commands

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
