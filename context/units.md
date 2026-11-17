# Units — Atomic Sequential Build Plan (Unit 1 → Unit 10)

> Execute strictly in order. Each unit must leave the repo compiling, `flutter analyze` clean, and `flutter test` green (see `5-ai-workflow-rules.md`).
> Contracts referenced as §x.y point to `context/2-architecture.md` unless stated otherwise.

---

## Unit 1 — Scaffold, Dependencies & Zero-Secret Repository

**Depends on:** none
**Input files:** `context/2-architecture.md` §2.1, `context/4-code-standards.md` §4.1, §4.2, §4.6

**Tasks**
1. `flutter create --platforms=android --org com.navisense --project-name navisense .`
2. Delete any non-Android platform folders if created (`ios/`, `web/`, `linux/`, `macos/`, `windows/`).
3. Write `pubspec.yaml` exactly per §2.1. Run `flutter pub get`, then replace each `any` with the resolved caret version from `pubspec.lock`.
4. Convert the Android build to `build.gradle.kts` per §2.1 (minSdk 26, compileSdk 36, targetSdk 36, BoM 35.2.0, `firebase-ai-ondevice:16.0.0-beta08`). Add the `com.google.gms.google-services` plugin in `settings.gradle.kts`.
5. `AndroidManifest.xml`: `CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE`, `VIBRATE` permissions. `<uses-feature android:name="android.hardware.camera" android:required="true"/>`. Add `<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>` for `flutter_tts` on API 30+.
6. `.gitignore` zero-secret block (§4.6). `secrets.example.json`.
7. Root `LICENSE`: the **unmodified** Apache License 2.0 text from https://www.apache.org/licenses/LICENSE-2.0.txt, with the appendix copyright line `Copyright 2026 NaviSense Contributors` in the README, not inside the license body.
8. `analysis_options.yaml` per §4.2.
9. Minimal `lib/main.dart` rendering a Deep Navy scaffold with "NaviSense" in Cream (temporary until Unit 10, but production-quality: themed and with semantics label).

**Target output files**
`pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.gitignore`, `secrets.example.json`, `LICENSE`, `README.md` (title + license badge + build prerequisites), `android/settings.gradle.kts`, `android/build.gradle.kts`, `android/app/build.gradle.kts`, `android/app/proguard-rules.pro`, `android/app/src/main/AndroidManifest.xml`, `lib/main.dart`, `lib/core/theme/navi_colors.dart`

**Acceptance criteria**
- [ ] `flutter analyze` → No issues found
- [ ] `flutter build apk --debug` succeeds. `aapt dump badging` shows `sdkVersion:'26'` and `targetSdkVersion:'36'`
- [ ] `git status` with dummy `secrets.json`, `google-services.json`, and `lib/firebase_options.dart` present shows none of them as untracked
- [ ] `git grep -nE "dart:js_interop|package:web|idb_shim|ReCaptcha"` returns nothing
- [ ] After push, GitHub "About" panel shows **Apache-2.0**

---

## Unit 2 — Firebase Bootstrap, App Check & Remote Config Governance

**Depends on:** Unit 1
**Input files:** §2.8, §2.9, `context/4-code-standards.md` §4.4, §4.7

**Tasks**
1. Run `flutterfire configure --platforms=android` (generates gitignored `lib/firebase_options.dart` and `android/app/google-services.json`).
2. `AppCheckBootstrap.activate()`: debug provider with `String.fromEnvironment('APP_CHECK_DEBUG_TOKEN')` when `kDebugMode`, Play Integrity otherwise (§2.8). If the token is empty in debug, log a warning naming the README section.
3. `RemoteConfigService`: defaults, settings, non-blocking `fetchAndActivate`, `onConfigUpdated` subscription, whitelist `{navisense_nav_prompt_v1, navisense_nav_prompt_v2}`, typed getters (`activePromptTemplate`, `cloudTimeout`, `ttsVoiceName`, `enableCloudTts`).
4. Riverpod providers: `remoteConfigServiceProvider`, `promptTemplateProvider` (`Notifier<String>`), with subscription cancelled in `ref.onDispose`.
5. `main.dart` bootstrap order: `WidgetsFlutterBinding.ensureInitialized()` → `Firebase.initializeApp` → App Check → `ProviderScope` → `runApp`. Remote Config init runs inside a provider, not blocking the first frame.

**Target output files**
`lib/main.dart`, `lib/core/security/app_check_bootstrap.dart`, `lib/core/config/remote_config_service.dart`, `lib/core/errors/navi_failure.dart`, `test/core/remote_config_service_test.dart`

**Acceptance criteria**
- [ ] Unit tests: unknown template value → `navisense_nav_prompt_v1`. Valid v2 → v2. An update event without the key doesn't change state
- [ ] On device (debug, real token): logcat shows App Check token obtained with no `App attestation failed`
- [ ] Changing `active_prompt_template` in the console updates `promptTemplateProvider` on a running device within ≤ 10 s, with no app restart (log line `navisense.rc template=navisense_nav_prompt_v2`)
- [ ] App launches and renders its first frame in Airplane Mode (RC defaults used, no crash)

---

## Unit 3 — Camera Service, Frame Throttling & Memory Lifecycle

**Depends on:** Unit 2
**Input files:** `context/4-code-standards.md` §4.5, `context/3-ui-context.md` §3.8

**Tasks**
1. `CameraControllerNotifier` (`AsyncNotifier<CameraController>`): back camera, `ResolutionPreset.medium`, `enableAudio: false`, `ImageFormatGroup.nv21`.
2. `CameraService`: `startStream(onFrame)` with 700 ms throttle + busy flag. `captureSnapshot()` = stop stream → `takePicture()` → native `compressJpeg(path, maxEdge: 768, quality: 70)` → delete original file → restart stream → return `Uint8List` (≤ ~120 KB typical).
3. `WidgetsBindingObserver` lifecycle: dispose on `inactive`/`paused`, re-init on `resumed`.
4. Kotlin: in `MainActivity.kt`, register MethodChannel `navisense/gemini_nano` with `compressJpeg` and `getDeviceMemoryClass` (returns `ActivityManager.memoryClass` and `totalMem`). `generate`/`getStatus` arrive in Unit 6, so for now the handler returns `notImplemented()` for unknown methods.
5. Camera permission flow with spoken rationale (uses `flutter_tts` directly here and is refactored onto `LocalTtsService` in Unit 5) and a settings deep-link on permanent denial.
6. `CameraPreviewLayer` widget wrapped in `ExcludeSemantics`, dimmed by an overlay `Container(color: navyDeep.withValues(alpha: 0.65))`.

**Target output files**
`lib/features/camera/camera_service.dart`, `lib/features/camera/camera_controller_provider.dart`, `lib/features/camera/widgets/camera_preview_layer.dart`, `android/app/src/main/kotlin/com/navisense/app/MainActivity.kt`, `test/camera/throttle_test.dart`

**Acceptance criteria**
- [ ] Unit test with fake clock: 10 frames at 100 ms intervals → exactly 2 processed (t=0, t=700). Frames during busy are dropped
- [ ] Snapshot JPEG long edge ≤ 768 px and original temp file deleted (asserted via file existence check in an integration log)
- [ ] Backgrounding then resuming the app 20× causes no `CameraException` and no PSS growth > 5 MB
- [ ] Redmi A3: 10-minute preview + stream soak → TOTAL PSS < 150 MB

---

## Unit 4 — Google ML Kit Stage 0: `SpatialSceneSummary` Service

**Depends on:** Unit 3
**Input files:** §2.3, `context/4-code-standards.md` §4.5.8

**Tasks**
1. `spatial_math.dart`: pure functions `directionFor(Rect box, Size frame)`, `distanceFor(Rect box, Size frame)`, `isObstacle(Direction, Distance)` with the exact thresholds in §2.3 (0.33 / 0.67; 0.25 / 0.06).
2. `SpatialSceneSummary`, `SpatialEntity`, enums, and `toPromptString()` exactly per §2.3.
3. `MlKitPerceptionService`: single instances of `ObjectDetector` (stream mode, classify, multiple), `ImageLabeler(confidenceThreshold: 0.65)`, `TextRecognizer(latin)`. `perceive(InputImage) → Future<SpatialSceneSummary>` runs the three detectors sequentially with a 1000 ms overall timeout. Label fusion and OCR filtering per §2.3. Sort entities obstacles-first → distance → confidence. Cap at 5 entities.
4. `InputImage` construction from NV21 `CameraImage` with correct `InputImageRotation` from `sensorOrientation` + device orientation, and `InputImage.fromFilePath` for snapshots.
5. `perceptionProvider` (`Notifier<SpatialSceneSummary?>`) holds only the latest summary plus `isStale` (> 2 s).
6. `ref.onDispose` closes all three detectors.

**Target output files**
`lib/features/mlkit_perception/spatial_math.dart`, `lib/features/mlkit_perception/models/spatial_scene_summary.dart`, `lib/features/mlkit_perception/mlkit_perception_service.dart`, `lib/features/mlkit_perception/perception_provider.dart`, `test/mlkit_perception/spatial_math_test.dart`, `test/mlkit_perception/summary_serialization_test.dart`

**Acceptance criteria**
- [ ] Boundary tests: xCenter 0.329 → LEFT, 0.33 → CENTER, 0.67 → CENTER, 0.671 → RIGHT. Area 0.25 → VERY_CLOSE, 0.2499 → AHEAD, 0.06 → AHEAD, 0.0599 → FAR
- [ ] Golden: entities {Chair, CENTER, VERY_CLOSE, 0.88}, {Door, LEFT, AHEAD, 0.79}, texts ["EXIT"] → `[Obstacle: Chair, CENTER, VERY CLOSE (88%)], [Object: Door, LEFT, AHEAD (79%)], [Text: "EXIT"]`
- [ ] Labels with confidence < 0.65 never appear
- [ ] On device: median `processingMs` ≤ 50 ms on the flagship and ≤ 120 ms on Redmi A3 over 50 frames (logged)
- [ ] No `CameraImage` or `InputImage` stored in any field (code review + `git grep "CameraImage? _"` returns nothing)

---

## Unit 5 — Tier 3 Deterministic Spatial Formatter & Local TTS

**Depends on:** Unit 4
**Input files:** §2.6, §2.7 (flutter_tts init), `context/3-ui-context.md` §3.4

**Tasks**
1. `DeterministicSpatialFormatter.format(SpatialSceneSummary, {bool textOnly = false}) → String` implementing the rules in §2.6 exactly (≤ 4 sentences, label capitalization, `textOnly` mode emits only "Sign reads …" sentences or "No text found.").
2. `LocalTtsService`: one `FlutterTts` instance; init per §2.7 (`awaitSpeakCompletion(true)`, `setSpeechRate(0.45)`, `setPitch(1.0)`, `setVolume(1.0)`, `setLanguage('en-US')`); `speak(text)`, `stop()`, `setRate(double)`; `isAvailable` from `getEngines` + `isLanguageInstalled`. If unavailable, `speak` throws `VoiceFailure`.
3. `ConnectivityProbe.isOffline()`: `InternetAddress.lookup('firebasevertexai.googleapis.com')` with a 300 ms timeout, result cached 5 s.
4. Temporary wiring in `main.dart` debug builds only: a tap triggers perceive → format → speak. It is replaced by the orchestrator in Unit 9.

**Target output files**
`lib/features/ai_orchestrator/deterministic_spatial_formatter.dart`, `lib/features/voice/local_tts_service.dart`, `lib/core/connectivity/connectivity_probe.dart`, `test/ai_orchestrator/formatter_test.dart`

**Acceptance criteria**
- [ ] Golden: §2.6 example → exactly `Caution: Chair very close ahead in center. Door on your left. Sign reads EXIT.`
- [ ] Golden: empty summary → `Path looks clear. No objects detected.`
- [ ] Golden: {Table, RIGHT, FAR} → `Table further to the right.`
- [ ] 6 entities in → ≤ 4 sentences out. Output is identical across 100 runs (deterministic)
- [ ] Redmi A3 in Airplane Mode: tap → audible speech start ≤ 300 ms (measured from tap log to `setStartHandler` callback)

---

## Unit 6 — Tier 1 Gemini Nano 4 Hybrid Bridge (Kotlin ↔ Dart)

**Depends on:** Unit 5
**Input files:** §2.4, `context/4-code-standards.md` §4.3, §4.7

**Tasks**
1. `GeminiNanoBridge.kt` per §2.4: lazy `GenerativeModel` with `OnDeviceConfig(mode = InferenceMode.PREFER_ON_DEVICE)` and `systemInstruction`; `getStatus` via `GenerativeModel.OnDeviceExtension.checkStatus()`; `startDownload` via `OnDeviceExtension.download()` with progress on EventChannel `navisense/gemini_nano/download`; `generate` with `ImagePart` (bitmap) + `TextPart` (summary), a 4000 ms timeout, returning `text`, `inferenceSource`, and `latencyMs`.
2. `SafeResult` wrapper guaranteeing single reply. Bitmap recycled in `finally`.
3. Merge the bridge into the existing `navisense/gemini_nano` handler from Unit 3 (keeping `compressJpeg` / `getDeviceMemoryClass`).
4. **Verify every API symbol** against firebase-ai 18.2.0 / ondevice 16.0.0-beta08 at compile time. Any deviation gets recorded as `CONTRACT CHANGE` in `2-architecture.md` §2.4 + tracker changelog.
5. Dart `NanoBridge`: typed `Future<NanoStatus> getStatus()`, `Future<void> startDownload()`, `Stream<NanoDownloadProgress> downloadProgress`, `Future<NanoResult> generate({required Uint8List jpeg, required String summary, required String systemInstruction})`. Maps `PlatformException` → `NanoFailure`. Wraps the call in a 4500 ms Dart-side timeout → `TimeoutFailure`.
6. `nanoStatusProvider` (`AsyncNotifier<NanoStatus>`) re-checked on app resume and after a download completes. `nanoDownloadProgressProvider` (`StreamProvider`).

**Target output files**
`android/app/src/main/kotlin/com/navisense/app/GeminiNanoBridge.kt`, `android/app/src/main/kotlin/com/navisense/app/MainActivity.kt`, `lib/features/ai_orchestrator/nano_bridge.dart`, `test/ai_orchestrator/nano_bridge_test.dart`

**Acceptance criteria**
- [ ] `./gradlew :app:compileDebugKotlin` succeeds with no deprecated `FirebaseAIOnDevice.*` usages (`git grep FirebaseAIOnDevice` returns nothing)
- [ ] Dart tests with `TestDefaultBinaryMessengerBinding` mock: status mapping, `NANO_TIMEOUT` → `NanoFailure(code: NANO_TIMEOUT)`, malformed map → `NanoFailure(code: NANO_FAILED)`
- [ ] Flagship device: `generate` returns non-empty text with `inferenceSource == "ON_DEVICE"` in Airplane Mode
- [ ] Redmi A3: `getStatus` returns `UNAVAILABLE` within 500 ms with no crash, and the bridge never instantiates download

---

## Unit 7 — Tier 2 Cloud Reasoning via Server Prompt Templates

**Depends on:** Unit 6
**Input files:** §2.5 (Reasoning + Dotprompt templates), §2.9, `context/4-code-standards.md` §4.7

**Tasks**
1. In the Firebase console (AI Logic → Prompt templates), create `navisense_nav_prompt_v1` and `navisense_nav_prompt_v2` with the exact Dotprompt bodies from §2.5. Verify the input variable names `scene`, `image`, and `locale`.
2. `CloudReasoningService.reason({required Uint8List jpeg, required SpatialSceneSummary summary}) → Future<CloudReasoningResult>`: uses `FirebaseAI.googleAI(appCheck: FirebaseAppCheck.instance).templateGenerativeModel()`, template ID from `promptTemplateProvider`, timeout from `cloudTimeout` (default 1500 ms), maps `SocketException`/`TimeoutException`/`FirebaseException` → `NaviFailure` subtypes, and rejects empty/blocked text as `FirebaseAiFailure(code: 'empty')`.
3. Result carries `text`, `templateId`, and `latencyMs` for telemetry.
4. The service is exposed via `cloudReasoningServiceProvider`. `FirebaseAI` is injected for test overrides.

**Target output files**
`lib/features/ai_orchestrator/cloud_reasoning_service.dart`, `lib/features/ai_orchestrator/models/guidance_result.dart`, `test/ai_orchestrator/cloud_reasoning_service_test.dart`, `context/2-architecture.md` (only if the template API differs, as a CONTRACT CHANGE)

**Acceptance criteria**
- [ ] Tests (mocked model): a delayed response of 1600 ms → `TimeoutFailure`. `SocketException` → `NetworkFailure`. `FirebaseException(code: 'permission-denied')` → `FirebaseAiFailure` with code. Empty text → `FirebaseAiFailure(code: 'empty')`
- [ ] Test: template ID passed equals the current `promptTemplateProvider` value. Switching the provider mid-session changes the next call's ID
- [ ] Device (App Check enforcement ON): real call returns guidance text in ≤ 1500 ms on Wi-Fi
- [ ] Remote Config switch v1 → v2 produces clock-face phrasing on the next tap without restart

---

## Unit 8 — Cloud TTS, PCM→WAV Codec & SHA-256 Audio Cache

**Depends on:** Unit 7
**Input files:** §2.5 (Cloud TTS, RIFF table, cache), `context/4-code-standards.md` §4.5.9

**Tasks**
1. `wav_codec.dart`: `pcmToWav` exactly per §2.5 (odd-byte trim, LE fields, big-endian ASCII tags).
2. `wav_cache.dart`: `cacheKey(text, voice, model)` with normalization; `lookup(key) → File?` (touches mtime); `store(key, wavBytes)` atomically (`.tmp` → `rename`); `evict()` LRU to ≤ 20 MB and ≤ 200 files; directory `getApplicationDocumentsDirectory()/navisense_audio/` created lazily.
3. `CloudTtsService.synthesize(text) → Future<File>`: checks the cache first. On a miss it calls `gemini-3.1-flash-tts-preview` with audio modality and voice from Remote Config, 1500 ms timeout, takes `response.inlineDataParts.first.bytes`, then `pcmToWav` → store → return file. Throws `VoiceFailure` when `inlineDataParts` is empty, or when the `mimeType` isn't `audio/L16`/`audio/pcm`-compatible (log the actual mimeType and accept a `rate=24000` parameter if present).
4. `VoicePlayer`: one `AudioPlayer` (`PlayerMode.mediaPlayer`). `playFile(File)` via `DeviceFileSource`, `playBytes(Uint8List)` via `BytesSource(bytes, mimeType: 'audio/wav')`. Completes when `onPlayerComplete` fires. `stop()`. It also arbitrates with `LocalTtsService` so only one voice path is active.

**Target output files**
`lib/features/voice/wav_codec.dart`, `lib/features/voice/wav_cache.dart`, `lib/features/voice/cloud_tts_service.dart`, `lib/features/voice/voice_player.dart`, `test/voice/wav_codec_test.dart`, `test/voice/wav_cache_test.dart`

**Acceptance criteria**
- [ ] WAV test: 48 000 PCM bytes → output length 48 044. Bytes 0–3 = `52 49 46 46`. Bytes 4–7 = LE(48 036) = `A4 BB 00 00`. Bytes 22–23 = `01 00`. Bytes 24–27 = LE(24000) = `C0 5D 00 00`. Bytes 28–31 = LE(48000) = `80 BB 00 00`. Bytes 32–33 = `02 00`. Bytes 34–35 = `10 00`. Bytes 40–43 = LE(48 000) = `80 BB 00 00`
- [ ] Odd-length input (48 001) → data size 48 000
- [ ] Cache test (temp dir): identical normalized text → same key. Store then lookup hits. 21 MB of entries → evicted to ≤ 20 MB, oldest first. An interrupted write leaves no partial `.wav`
- [ ] Device: cloud voice plays. The second identical request plays from cache with no network call (logged `cache=hit`) and works in Airplane Mode

---

## Unit 9 — AI Orchestrator (3-Tier Router) & Telemetry

**Depends on:** Unit 8
**Input files:** §2.2, §2.4 (routing rule), §2.6 (triggers), §2.7 (state machine), `context/3-ui-context.md` §3.5, §3.7

**Tasks**
1. `AiOrchestrator extends AsyncNotifier<GuidanceResult?>` with `describe()`, `readText()`, `repeat()`, and `stop()`.
2. `describe()` flow: increment `requestId` → stop current voice → capture snapshot + get fresh/stale-checked summary → route:
   - Nano `AVAILABLE` → Tier 1 (`NanoBridge.generate`) → `LocalTtsService.speak`. Tier = `ON_DEVICE • Gemini Nano 4` (or `IN_CLOUD` if the bridge reports it).
   - Else, if online → Tier 2 (`CloudReasoningService` → `CloudTtsService` → `VoicePlayer`). On TTS failure, speak the cloud text locally (pill `IN_CLOUD • Gemini Flash • local voice`).
   - Else, or on any `NaviFailure` from Tier 1/2 → Tier 3 (formatter → cache lookup with the Tier-3 key → `VoicePlayer.playFile` on hit, else `LocalTtsService.speak`).
   - If all voice paths fail → `SemanticsService.announce(text)` + SOS haptic and set `AsyncError` carrying the text.
3. `readText()`: same routing with the `textOnly` formatter in Tier 3, and a template input `locale` plus a prefix "Read all visible text verbatim." in the Tier 1 summary.
4. `GuidanceResult`: `text`, `tier` (sealed: `Tier1Nano`, `Tier2Cloud(localVoice: bool)`, `Tier3Edge`), `stage0Ms`, `inferenceMs`, `templateId?`, `cacheHit`, and `hasVeryCloseObstacle`.
5. `TelemetryNotifier` (`Notifier<TelemetryState>`) derives the exact pill labels from §3.7.
6. Stale-result guard: drop any result whose `requestId` ≠ current.

**Target output files**
`lib/features/ai_orchestrator/ai_orchestrator.dart`, `lib/features/ai_orchestrator/models/guidance_result.dart`, `lib/features/telemetry/telemetry_notifier.dart`, `test/ai_orchestrator/orchestrator_routing_test.dart`, `test/telemetry/telemetry_notifier_test.dart`

**Acceptance criteria**
- [ ] Routing tests (all dependencies mocked) cover each transition in §2.7:
  1. Nano AVAILABLE + success → Tier1, local TTS called once
  2. Nano error + online → Tier2
  3. Nano error + offline → Tier3
  4. Nano unavailable + online + success → Tier2, VoicePlayer.playFile called
  5. Cloud `TimeoutFailure` → Tier3 within ≤ 1600 ms total
  6. Cloud TTS failure → local TTS speaks the cloud text, tier `Tier2Cloud(localVoice: true)`
  7. Tier3 cache hit → `playFile`, no flutter_tts
  8. All voice fails → announce called, `AsyncError` with text
- [ ] Stale-guard test: two rapid `describe()` calls → only the second result is emitted/spoken
- [ ] Pill label strings match §3.7 character-for-character (golden test)
- [ ] Device: three tiers demonstrated (flagship online, Redmi A3 online, Redmi A3 Airplane Mode)

---

## Unit 10 — TalkBack UI, Haptics, Release Build, README & Demo Readiness

**Depends on:** Unit 9
**Input files:** `context/3-ui-context.md` (all), `context/1-project-overview.md` §1.4, §1.7, §2.8

**Tasks**
1. `navi_theme.dart`: dark-only theme from the palette. 18sp minimum body, 22sp caption.
2. `HomeScreen`: full-screen `GestureSurface` (semantics + custom actions per §3.3), `TelemetryPill`, last-guidance caption, `NanoDownloadBanner` (states per §3.6, progress announcements every 25%, 7-day "Not now" persisted to a JSON file in app documents), and `BottomControls` (Repeat / Read / Settings, ≥ 72×72dp).
3. `ref.listen(aiOrchestratorProvider)` → tier haptics (§3.5) at audio start, VERY_CLOSE buzz, processing heartbeat every 800 ms, announcements per §3.4.
4. `SettingsScreen` per §3.9, persisted to the same JSON settings file.
5. Onboarding per §3.8 (first launch only).
6. Release signing with an upload keystore (gitignored `key.properties`). Register the SHA-256 in Firebase for Play Integrity. Turn ON App Check enforcement for Firebase AI Logic and Remote Config.
7. `README.md` complete:
   - What NaviSense is + architecture diagram + tier table
   - **For Judges** section:
     1. Install the release APK from GitHub Releases (works for Tier 2/3; Play Integrity requires an install from a trusted source. If attestation fails, use the debug build below).
     2. Debug build path: `git clone` → place the `google-services.json` and `lib/firebase_options.dart` provided privately by the team (or run `flutterfire configure` against your own project) → copy `secrets.example.json` to `secrets.json` → paste the **safelisted debug token** the team gives you (or send us the token logged by `DebugAppCheckProvider` on first launch: search logcat for `Enter this debug secret into the allow list`) → `flutter run --dart-define-from-file=secrets.json`. This must be a **debug** build: the App Check debug provider is only active when `kDebugMode` is true, and release builds always use Play Integrity.
     3. How to trigger each tier (flagship w/ AICore, any phone online, Airplane Mode).
     4. How to watch the Remote Config hot-swap.
   - Security model, memory budget results, license (Apache-2.0), and acknowledgements.
8. Tag `v1.0.0-hackathon` and attach the release APK.

**Target output files**
`lib/app.dart`, `lib/core/theme/navi_theme.dart`, `lib/core/utils/haptics.dart`, `lib/features/home/home_screen.dart`, `lib/features/home/settings_screen.dart`, `lib/features/home/widgets/gesture_surface.dart`, `lib/features/home/widgets/nano_download_banner.dart`, `lib/features/home/widgets/bottom_controls.dart`, `lib/features/telemetry/widgets/telemetry_pill.dart`, `README.md`, `android/app/build.gradle.kts` (signing), `test/home/touch_target_test.dart`, `test/home/semantics_test.dart`

**Acceptance criteria**
- [ ] Widget test: every node with a tap action has size ≥ 72×72dp (`meetsGuideline(androidTapTargetGuideline)` plus a custom 72dp matcher)
- [ ] Widget test: `meetsGuideline(textContrastGuideline)` and `labeledTapTargetGuideline` pass
- [ ] Widget test: the GestureSurface rect equals the screen rect. Pill shows the correct label/color per tier
- [ ] Manual TalkBack pass on both devices: every control reachable via swipe, the describe action works via double-tap, custom actions are listed, and nothing reads "unlabeled button" or "image"
- [ ] Haptic counts distinguishable blindfolded on Redmi A3 (2 / 1 / 3 pulses)
- [ ] `flutter build apk --release` succeeds. Release APK ≤ 60 MB arm64. Installed release passes App Check (console shows verified requests)
- [ ] 30-minute soak on Redmi A3 (taps every 10 s, mixed online/offline): 0 crashes, PSS < 150 MB, 0 silent failures
- [ ] Secret scan (§4.6) returns nothing. GitHub shows Apache-2.0. The README For Judges steps were validated on a clean machine
