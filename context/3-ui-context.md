# 3 — UI Context: Blind-First, TalkBack-Optimized Android UX

> **Design principle:** The primary user **cannot see the screen**. Every visual element is a second channel for low-vision users, sighted companions, and hackathon judges. Audio, haptics, and TalkBack semantics are the primary channel.

---

## 3.1 Palette (High Contrast)

| Token | Hex | Role | Contrast notes |
|---|---|---|---|
| `navyDeep` | `#141B41` | App background | Cream on Navy ≈ 15.9:1 (AAA) |
| `cream` | `#F7F5F0` | Primary text / icons | — |
| `goldAntique` | `#B18A41` | Brand, Tier 3 pill, focus rings | Gold on Navy ≈ 5.6:1 (AA normal, AAA large) |
| `emerald` | `#10B981` | Tier 1 pill (ON_DEVICE Nano) | Pill text = `navyDeep` on emerald ≈ 7.3:1 |
| `royalBlue` | `#3B82F6` | Tier 2 pill (IN_CLOUD) | Pill text = `navyDeep` bold 18sp on royal blue ≈ 4.6:1 (AA; AAA for large text). Never cream on blue (≈ 3.4:1) |
| `errorRed` | `#F87171` | Error banner border only (never sole indicator) | — |

```dart
abstract final class NaviColors {
  static const navyDeep = Color(0xFF141B41);
  static const cream = Color(0xFFF7F5F0);
  static const goldAntique = Color(0xFFB18A41);
  static const emerald = Color(0xFF10B981);
  static const royalBlue = Color(0xFF3B82F6);
  static const errorRed = Color(0xFFF87171);
}
```

Rules:
- Dark theme only. No light mode (it is less battery-friendly on OLED and adds glare for photophobic users).
- Color never carries meaning alone. Each tier also has a **text label**, an **icon**, and a **haptic pattern**.
- Respect system font scale up to **200%**. Layouts use `Flexible` / `FittedBox` and never clip.
- Minimum body text 18sp, pill text 18sp bold, last-guidance caption 22sp.

---

## 3.2 Touch Targets & Layout

- **Minimum touch target: 72×72dp** (above Material's 48dp). Enforced by a widget test that walks the semantics tree.
- The screen is a single **full-screen `GestureSurface`** that covers 100% of the viewport behind all chrome. A user who touches *anywhere* gets a result.
- Only three discrete controls exist, all ≥ 72dp, at the bottom edge (thumb zone):
  1. **Repeat** (bottom-left): replays the last guidance.
  2. **Read Text** (bottom-center): OCR-only mode.
  3. **Settings** (bottom-right): speech rate and haptics toggle.

```
┌────────────────────────────────────────┐
│ [AICore download banner — optional]    │  ← non-blocking, top, dismissible
│                                        │
│  ┌──────────────────────────────────┐  │
│  │ ● ON_DEVICE • Gemini Nano 4 •    │  │  ← Judge Telemetry Pill (top-center)
│  │   0ms • $0                       │  │
│  └──────────────────────────────────┘  │
│                                        │
│         (camera preview, dimmed        │
│          to 35% for low vision;        │
│          entire area = GestureSurface) │
│                                        │
│  "Caution: Chair very close ahead in   │  ← Last guidance caption, 22sp cream
│   center. Door on your left."          │
│                                        │
│ ┌────────┐   ┌────────┐   ┌────────┐   │
│ │ Repeat │   │  Read  │   │Settings│   │  ← 72×72dp min, gold outline
│ └────────┘   └────────┘   └────────┘   │
└────────────────────────────────────────┘
```

---

## 3.3 Gesture Vocabulary

| Gesture (TalkBack OFF) | Gesture (TalkBack ON) | Action |
|---|---|---|
| Single tap | Double-tap (TalkBack activate) | **Describe scene** (full 3-tier pipeline) |
| Long-press (≥ 500 ms) | Double-tap-and-hold | **Read text** (OCR priority; formatter emits only texts) |
| Double-tap | Custom action "Repeat" (swipe up/down actions menu) | **Repeat last guidance** |
| Two-finger tap | Magic tap (two-finger double-tap) | **Stop speaking** |

Implementation:

```dart
Semantics(
  container: true,
  label: 'NaviSense camera. Double tap to describe your surroundings.',
  hint: 'Double tap and hold to read text.',
  onTap: () => ref.read(aiOrchestratorProvider.notifier).describe(),
  onLongPress: () => ref.read(aiOrchestratorProvider.notifier).readText(),
  customSemanticsActions: {
    const CustomSemanticsAction(label: 'Repeat last guidance'):
        () => ref.read(aiOrchestratorProvider.notifier).repeat(),
    const CustomSemanticsAction(label: 'Stop speaking'):
        () => ref.read(aiOrchestratorProvider.notifier).stop(),
  },
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: ..., onLongPress: ..., onDoubleTap: ...,
    child: const CameraPreviewLayer(),
  ),
)
```

- Native magic tap is handled with an `Actions`/`Shortcuts` mapping where available. Otherwise "Stop speaking" is reachable as a custom action.
- The camera preview itself is `ExcludeSemantics`, so TalkBack never reads "image".

---

## 3.4 TalkBack Semantics Rules

1. **Live region for guidance:** the caption is wrapped in `Semantics(liveRegion: true)` **only when TTS is unavailable**. When NaviSense is speaking, `SemanticsService.announce` is **not** called, so the guidance isn't read twice.
2. **Busy state:** while processing, the surface's semantics `value` = "Analyzing…". After 800 ms with no result, a soft tick haptic plays (`HapticFeedback.selectionClick`) every 800 ms as a heartbeat. The user always knows the app is working.
3. **Pill semantics:** `Semantics(label: 'Inference source: on device, Gemini Nano 4, zero network latency, zero cost')`. The pill is **not** focusable by default (`excludeSemantics` toggled by Settings → "Announce inference tier"). Judges can turn it on.
4. **Focus order:** Banner (if present) → GestureSurface → Repeat → Read → Settings. Enforced with `OrdinalSortKey`.
5. **No time-limited UI.** Banners persist until dismissed or resolved.
6. **Announcements** (via `SemanticsService.announce`) only for state changes: "Camera ready", "Offline mode, using on-device guidance", "Guidance style updated", "On-device AI ready".

---

## 3.5 Haptic Patterns per Tier

Haptics fire **at the moment audio starts**, so the user feels the tier before hearing the content.

| Event | Pattern | Implementation |
|---|---|---|
| Tap acknowledged | 1 × light | `HapticFeedback.lightImpact()` |
| **Tier 1** — ON_DEVICE Gemini Nano 4 | 2 × medium, 80 ms gap ("da-dum") | `mediumImpact(); await 80ms; mediumImpact();` |
| **Tier 2** — IN_CLOUD Gemini Flash TTS | 1 × heavy ("dum") | `HapticFeedback.heavyImpact()` |
| **Tier 3** — ML Kit Edge Fallback | 3 × light, 60 ms gaps ("tik-tik-tik") | `lightImpact()` ×3 |
| Processing heartbeat | selection click every 800 ms | `HapticFeedback.selectionClick()` |
| VERY_CLOSE obstacle in result | Additional `vibrate()` long buzz *before* speech | `HapticFeedback.vibrate()` |
| Total failure (no voice possible) | SOS: 3 short, 3 heavy, 3 short | sequence helper |

```dart
abstract final class TierHaptics {
  static Future<void> tier1() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
  }
  static Future<void> tier2() => HapticFeedback.heavyImpact();
  static Future<void> tier3() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.lightImpact();
      if (i < 2) await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }
}
```

Settings has a "Haptics" toggle (default ON). Many Android Go devices have weak actuators, so heavy vs. light may feel similar there. The *count* of pulses is the reliable discriminator.

---

## 3.6 Non-Blocking AICore Model Download Banner

Shown **only** when `getStatus()` returns `DOWNLOADABLE` or `DOWNLOADING`. Never shown on `UNAVAILABLE` devices (Redmi A3), because those users can do nothing about it.

| State | Banner text (also announced once) | Actions (72dp) |
|---|---|---|
| `DOWNLOADABLE` | "Faster on-device AI is available for your phone. Download now? About 1 GB on Wi-Fi recommended." | **Download** / **Not now** |
| `DOWNLOADING` | "Downloading on-device AI: 42%. NaviSense works normally meanwhile." | **Hide** |
| Completed → `AVAILABLE` | Banner closes; announce "On-device AI ready." | — |
| Error | "On-device AI download paused. NaviSense will keep using cloud and offline guidance." | **Retry** / **Hide** |

- Progress announcements are throttled to every 25% so TalkBack doesn't get flooded.
- "Not now" is persisted for 7 days in `SharedPreferences`-free storage: a small JSON file in app documents, so no extra dependency.
- The banner sits *above* the gesture surface and only takes up its own height. Taps outside it still trigger describe.

---

## 3.7 Judge Telemetry Pill (3 States)

| State | Label (exact) | Background | Text color | Icon |
|---|---|---|---|---|
| Tier 1 | `ON_DEVICE • Gemini Nano 4 • 0ms • $0` | `#10B981` | `#141B41` | `Icons.memory` |
| Tier 2 | `IN_CLOUD • Gemini Flash TTS` | `#3B82F6` | `#141B41` | `Icons.cloud` |
| Tier 2 (TTS failed) | `IN_CLOUD • Gemini Flash • local voice` | `#3B82F6` | `#141B41` | `Icons.cloud_off` outline |
| Tier 3 | `ON_DEVICE • ML Kit Edge Fallback • 0ms • $0` | `#B18A41` | `#141B41` | `Icons.offline_bolt` |
| Idle (before first query) | `READY • Tap anywhere` | transparent, gold border | `#F7F5F0` | `Icons.touch_app` |

- "0ms" means **0 ms network latency**, not inference time. A secondary line (12sp, shown only when Settings → "Judge mode" is ON) shows the measured values: `infer 640ms • stage0 38ms • template v2`.
- Pill transitions: `AnimatedContainer` 250 ms color crossfade. Disabled when `MediaQuery.disableAnimations` is true.
- Pill height ≥ 40dp, horizontal padding 16dp, radius 24dp. It is display-only, so it is exempt from the 72dp rule unless Judge mode makes it focusable. In that case it gets padded to 72dp.

---

## 3.8 Onboarding (First Launch Only, ≤ 20 s)

1. Spoken (via `flutter_tts`) + shown: "Welcome to NaviSense. I describe what's in front of your camera. I need camera access."
2. System camera permission dialog.
3. "Hold your phone at chest height, camera facing forward. Tap anywhere to hear what's ahead. Hold to read text."
4. Done → announce "Camera ready".

If the permission is denied, a full-screen 72dp+ button "Open settings to allow camera" appears with an explanation. No dead ends.

---

## 3.9 Settings Screen

| Setting | Control | Default |
|---|---|---|
| Speech rate | Slider 0.30–0.70, step 0.05, announces value | 0.45 |
| Haptics | Switch (72dp row) | On |
| Announce inference tier | Switch | Off |
| Judge mode (show telemetry detail) | Switch | Off |
| Clear audio cache | Button → confirm dialog | — |
| Licenses | `showLicensePage` | — |

All rows are `MergeSemantics` with a full-row tap target ≥ 72dp.
