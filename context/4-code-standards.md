# 4 — Code Standards (Flutter/Dart 3 + Kotlin, Android-Only)

---

## 4.1 Folder Structure

```
navisense/
├── LICENSE                         # Apache 2.0 full text (GitHub-detectable)
├── README.md
├── analysis_options.yaml
├── pubspec.yaml / pubspec.lock     # both committed
├── secrets.example.json            # committed template
├── secrets.json                    # GITIGNORED
├── context/                        # AI/human project context (this folder)
├── android/
│   ├── app/
│   │   ├── build.gradle.kts
│   │   ├── proguard-rules.pro
│   │   ├── google-services.json    # GITIGNORED
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/com/navisense/app/
│   │           ├── MainActivity.kt
│   │           └── GeminiNanoBridge.kt
│   └── build.gradle.kts / settings.gradle.kts
├── lib/
│   ├── main.dart                   # bootstrap only (Firebase, App Check, RC, runApp)
│   ├── app.dart                    # MaterialApp, theme, routes
│   ├── firebase_options.dart       # GITIGNORED (flutterfire configure)
│   ├── core/
│   │   ├── config/remote_config_service.dart
│   │   ├── security/app_check_bootstrap.dart
│   │   ├── errors/navi_failure.dart
│   │   ├── connectivity/connectivity_probe.dart
│   │   ├── theme/navi_colors.dart
│   │   ├── theme/navi_theme.dart
│   │   └── utils/{haptics.dart, clock.dart, result.dart}
│   └── features/
│       ├── camera/
│       │   ├── camera_service.dart
│       │   ├── camera_controller_provider.dart
│       │   └── widgets/camera_preview_layer.dart
│       ├── mlkit_perception/
│       │   ├── models/spatial_scene_summary.dart
│       │   ├── spatial_math.dart
│       │   ├── mlkit_perception_service.dart
│       │   └── perception_provider.dart
│       ├── ai_orchestrator/
│       │   ├── nano_bridge.dart
│       │   ├── cloud_reasoning_service.dart
│       │   ├── deterministic_spatial_formatter.dart
│       │   ├── ai_orchestrator.dart          # AsyncNotifier + tier router
│       │   └── models/guidance_result.dart
│       ├── voice/
│       │   ├── wav_codec.dart                # pcmToWav
│       │   ├── wav_cache.dart                # sha256 + LRU
│       │   ├── cloud_tts_service.dart
│       │   ├── local_tts_service.dart
│       │   └── voice_player.dart             # audioplayers + flutter_tts arbitration
│       ├── telemetry/
│       │   ├── telemetry_notifier.dart
│       │   └── widgets/telemetry_pill.dart
│       └── home/
│           ├── home_screen.dart
│           ├── widgets/{gesture_surface.dart, nano_download_banner.dart, bottom_controls.dart}
│           └── settings_screen.dart
└── test/
    ├── mlkit_perception/spatial_math_test.dart
    ├── ai_orchestrator/{formatter_test.dart, orchestrator_routing_test.dart}
    ├── voice/{wav_codec_test.dart, wav_cache_test.dart}
    ├── core/remote_config_service_test.dart
    └── home/{touch_target_test.dart, semantics_test.dart}
```

**Rule:** a feature may import from `core/` and from its **own** folder. Cross-feature imports go only through the public provider file (for example `perception_provider.dart`). Only `ai_orchestrator` may depend on `mlkit_perception`, `voice`, and `telemetry`.

---

## 4.2 Dart 3 Standards

- `analysis_options.yaml`:
  ```yaml
  include: package:flutter_lints/flutter.yaml
  analyzer:
    language:
      strict-casts: true
      strict-inference: true
      strict-raw-types: true
    errors:
      unawaited_futures: error
      avoid_print: error
      always_declare_return_types: error
  linter:
    rules:
      - prefer_final_locals
      - prefer_const_constructors
      - avoid_dynamic_calls
      - unawaited_futures
      - cancel_subscriptions
      - close_sinks
      - use_build_context_synchronously
      - require_trailing_commas
  ```
- Use `final class` / `sealed class` for models. Use exhaustive `switch` expressions on sealed types and enums. No `default:` on enums.
- Immutable models: `const` constructors, `copyWith` handwritten (no codegen, to keep build simple and fast).
- **No `dynamic`** except at the `MethodChannel` boundary. There it is decoded immediately into typed models with explicit validation.
- No `print`. Use `dart:developer` `log()` with `name: 'navisense.<feature>'`. Release builds strip verbose logs through a `kReleaseMode` guard.
- Every `Future` is either awaited or explicitly `unawaited(...)` with a comment.
- Public APIs have `///` doc comments. Use `// WHY:` comments for non-obvious decisions only.
- Max file length 300 lines, max function length 50 lines (the orchestrator router excepted, ≤ 80).

## 4.3 Kotlin Standards

- Kotlin 2.x, JVM 17. Coroutines only: no `Thread`, no `AsyncTask`, no RxJava.
- A `CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)` is owned by `MainActivity` and cancelled in `onDestroy`.
- Heavy work (bitmap decode) goes on `Dispatchers.Default`. Every `Bitmap` is `recycle()`d in `finally`.
- `MethodChannel.Result` is called **exactly once** per invocation. Guard it with a small `AtomicBoolean` wrapper `SafeResult`.
- No secrets, no API keys, no hard-coded tokens. The debug App Check token comes from `BuildConfig` and only in the `debug` variant.
- `ktlint` default style. No wildcard imports except `kotlinx.coroutines.*`.

---

## 4.4 Riverpod State Management Rules

- Use `flutter_riverpod` with **manual providers** (no codegen) to keep the toolchain light.
- **`AsyncNotifier`** for async state with lifecycle: `AiOrchestrator`, `CameraControllerNotifier`, `NanoStatusNotifier`.
- **`Notifier`** for sync state: `TelemetryNotifier`, `PromptTemplateNotifier`, `SettingsNotifier`.
- **`Provider`** for stateless services (`WavCache`, `CloudTtsService`, `DeterministicSpatialFormatter`), with dependencies injected via `ref.watch`.
- **`StreamProvider`** for `nanoDownloadProgressProvider` (EventChannel).
- No `StateProvider`, no `ChangeNotifierProvider`, no global singletons except Firebase SDK instances. Firebase instances are wrapped in providers so tests can override them.
- Resource cleanup lives in `ref.onDispose(...)`: detectors `.close()`, camera `.dispose()`, subscriptions `.cancel()`, `AudioPlayer.dispose()`, `FlutterTts.stop()`.
- Widgets use `ref.watch` for rendering and `ref.read(...notifier)` in callbacks. **Never** call `ref.read` inside `build` for reactive data.
- `ref.listen` drives side-effects (haptics, announcements) in `HomeScreen`, not inside notifiers. Notifiers stay UI-agnostic and testable.

```dart
final aiOrchestratorProvider =
    AsyncNotifierProvider<AiOrchestrator, GuidanceResult?>(AiOrchestrator.new);
```

---

## 4.5 Camera Frame Throttling & Memory Lifecycle (3 GB RAM Rules)

**Budget:** total app PSS **< 150 MB** on Redmi A3 (Android Go, 3 GB). Breakdown target: Flutter engine + Dart heap ~60 MB, camera ~25 MB, ML Kit models + native ~45 MB, audio ~10 MB, headroom ~10 MB.

1. **Resolution:** `ResolutionPreset.medium` (≈ 720×480) for the stream. Never `high`/`max` on devices with `totalMem < 4 GB` (read once via a tiny `getDeviceMemoryClass` method on the existing channel).
2. **Format:** `imageFormatGroup: ImageFormatGroup.nv21` (directly consumable by ML Kit on Android, no YUV→RGB conversion in Dart).
3. **Throttle:** process at most **one frame every 700 ms** (`≈1.4 fps`) and **never while busy**:
   ```dart
   void _onFrame(CameraImage image) {
     final now = _clock.nowMs();
     if (_busy || now - _lastProcessedMs < 700) return; // drop: buffer released on return
     _busy = true;
     _lastProcessedMs = now;
     final input = _toInputImage(image); // copies plane bytes once
     // DO NOT retain `image` beyond this synchronous call.
     unawaited(_perceive(input).whenComplete(() => _busy = false));
   }
   ```
4. **Dispose immediately:**
   - Never store a `CameraImage` in a field, list, or provider. Its planes are native buffers reused by the camera plugin. Copy bytes once into the `InputImage` and drop the reference.
   - Null the `InputImage` reference right after `processImage` completes (local variable scope only). Never put it in state.
   - Snapshot JPEG files: `File(path).delete()` in `finally` after the request.
   - `Uint8List` JPEG / PCM / WAV buffers are local only. The cache stores **files**, not in-memory bytes.
5. **Pause on background:** `WidgetsBindingObserver.didChangeAppLifecycleState`:
   - `inactive`/`paused` → `stopImageStream()`, `controller.dispose()`, stop TTS/audio.
   - `resumed` → re-initialize the camera (new controller).
6. **Pause stream during tap capture:** `stopImageStream()` → `takePicture()` → `startImageStream()` after the JPEG is read. Concurrent streaming + capture on low-end HALs causes OOM and HAL errors.
7. **Snapshot downscale:** JPEG for AI is resized to max 768 px long edge, quality 70, **natively** in Kotlin via the `compressJpeg` method on `navisense/gemini_nano` (`BitmapFactory.Options.inSampleSize` + `Bitmap.createScaledBitmap` + `Bitmap.compress(JPEG, 70)`, `recycle()` in `finally`). Do not use `dart:ui` codecs: re-encoding to PNG would blow up memory. The Dart side never decodes full-resolution pixels.
8. **ML Kit detectors:** create exactly one instance of each per app lifetime and `close()` on dispose. Never create a detector per frame.
9. **Audio:** reuse one `AudioPlayer` with `PlayerMode.mediaPlayer`. Use `DeviceFileSource` for cached files (streams from disk).
10. **Verification:** `adb shell dumpsys meminfo com.navisense.app` after 10 minutes of continuous use plus 100 taps must show TOTAL PSS < 150 MB and no monotonic growth (leak check: sample every 2 minutes).

---

## 4.6 Zero-Secret `.gitignore` Policy

Mandatory entries (in addition to the Flutter defaults):

```gitignore
# --- NaviSense zero-secret policy ---
lib/firebase_options.dart
android/app/google-services.json
secrets.json
*.jks
*.keystore
android/key.properties
android/local.properties
.env
.env.*

# build / IDE
build/
.dart_tool/
.idea/
*.iml
.vscode/
android/.gradle/
android/app/release/
```

- `secrets.example.json` **is** committed with placeholder `"APP_CHECK_DEBUG_TOKEN": "<paste-your-safelisted-debug-token>"`.
- There are **no API keys in Dart or Kotlin source, ever**. Firebase AI Logic is called through the Firebase SDK, protected by App Check. The Gemini API key lives only in the Firebase project.
- Pre-commit check (documented in README; run manually or via a git hook):
  ```powershell
  git diff --cached --name-only | Select-String -Pattern 'google-services.json|firebase_options.dart|secrets.json|\.jks$'
  git grep -nE 'AIza[0-9A-Za-z_\-]{35}' -- ':!context/'
  ```
  Both must return nothing.

---

## 4.7 Error Handling Contracts

### Failure taxonomy

```dart
sealed class NaviFailure implements Exception {
  const NaviFailure(this.message);
  final String message;
}
final class NetworkFailure extends NaviFailure { const NetworkFailure(super.message); }      // SocketException, offline
final class TimeoutFailure extends NaviFailure { const TimeoutFailure(super.message); }      // TimeoutException
final class FirebaseAiFailure extends NaviFailure {                                          // FirebaseException / AI errors
  const FirebaseAiFailure(super.message, {this.code});
  final String? code;
}
final class NanoFailure extends NaviFailure {                                                // PlatformException from bridge
  const NanoFailure(super.message, {required this.code});
  final String code; // NANO_UNAVAILABLE | NANO_TIMEOUT | NANO_FAILED
}
final class PerceptionFailure extends NaviFailure { const PerceptionFailure(super.message); } // ML Kit
final class VoiceFailure extends NaviFailure { const VoiceFailure(super.message); }           // TTS / audio
final class CameraFailure extends NaviFailure { const CameraFailure(super.message); }
```

### Contracts
1. **Services throw only `NaviFailure` subtypes.** Each service maps raw exceptions at its boundary:
   ```dart
   } on SocketException catch (e) { throw NetworkFailure(e.message); }
     on TimeoutException { throw const TimeoutFailure('cloud reasoning > 1500ms'); }
     on FirebaseException catch (e) { throw FirebaseAiFailure(e.message ?? 'firebase', code: e.code); }
   ```
2. **The orchestrator never throws to the UI.** Every failure in Tier 1/2 is caught and routed to the next tier. Its `AsyncValue` only becomes `AsyncError` when Tier 3 **and** all voice paths fail. Even then the UI shows the text and triggers the SOS haptic.
3. **Perception failure is non-fatal.** The orchestrator continues with an empty `SpatialSceneSummary` and the image alone (Tier 1/2), or with "I couldn't see clearly. Please try again." (Tier 3).
4. **Timeouts are mandatory** on every cross-boundary await: cloud reasoning 1500 ms, cloud TTS 1500 ms, Nano 4000 ms, ML Kit 1000 ms, camera capture 2000 ms, connectivity probe 300 ms.
5. **Stale-result guard:** every request carries an incrementing `requestId`. Results whose id ≠ current id are discarded silently.
6. **No empty catches.** Every catch either rethrows a mapped failure or logs with `log(..., error: e, stackTrace: st)` and routes.

---

## 4.8 Testing Standards

- Pure logic (spatial math, formatter, WAV codec, cache key, routing decisions) has **≥ 90% line coverage**.
- Firebase, ML Kit, camera, and the channel are behind interfaces, mocked with `mocktail` in tests.
- Golden strings for the formatter live in `test/ai_orchestrator/formatter_test.dart` and **must not change** without updating `context/2-architecture.md` §2.6.
- Widget tests assert: every tappable semantics node ≥ 72×72dp; the GestureSurface covers the full screen; the pill label matches the tier.
- Commands: `flutter analyze` (0 issues) and `flutter test` (all green) before every commit.

## 4.9 Git Conventions

- Branch: `main` (protected in spirit; tag releases). Work happens in short-lived `unit-N-<slug>` branches or direct commits during the hackathon crunch.
- Commit format: `unit-N: <imperative summary>` e.g. `unit-4: add spatial math and SpatialSceneSummary`.
- Never commit generated `build/` or secret files (see §4.6).
