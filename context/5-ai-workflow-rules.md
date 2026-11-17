# 5 — AI Workflow Rules (for Claude Code / Cursor / Opus / Gemini agents)

> These rules are binding for any AI coding agent working in this repository. A human reviewer will reject work that violates them.

---

## 5.1 Before Writing Any Code

1. **Read the context, in order:**
   1. `context/1-project-overview.md` — what and why
   2. `context/2-architecture.md` — contracts, versions, channel APIs, math
   3. `context/3-ui-context.md` — UX, colors, haptics, semantics
   4. `context/4-code-standards.md` — structure, Riverpod, memory, errors
   5. `context/5-ai-workflow-rules.md` — this file
   6. `context/6-progress-tracker.md` — what is done
   7. `context/units.md` — the unit you are executing
2. **Identify the single next unit:** the lowest-numbered unit in `units.md` that isn't `[x] DONE` in `6-progress-tracker.md` and whose dependencies are all done.
3. **State the plan** in 3–7 bullets (files to create/modify, tests to add) before editing.
4. If the context files contradict each other, **stop and ask the human**. Do not guess. `2-architecture.md` wins on API contracts. `4-code-standards.md` wins on style.

## 5.2 Atomic Unit Execution Rules

- **One unit per session/PR.** Don't start Unit N+1 in the same change set as Unit N.
- Touch **only** the files listed in the unit's "Target output files". If another file must change, say why in the summary (for example, registering a provider in `main.dart`).
- Each unit ends in a **compilable, test-passing** state. No half-wired code behind commented-out blocks.
- **No placeholders:** no `// TODO`, `throw UnimplementedError()`, `pass`, or fake return values in production code. If something truly can't be finished, mark the unit `[~] IN_PROGRESS` with a written blocker.
- Keep diffs small and reviewable: ≤ ~600 changed lines per unit, excluding the generated lockfile.
- Don't refactor code from earlier units unless the current unit's acceptance criteria require it.

## 5.3 Verification Commands (run after every unit)

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze            # must report: No issues found!
flutter test               # must be all green
flutter build apk --debug --dart-define-from-file=secrets.json   # must succeed
```

For units touching Kotlin:
```powershell
cd android; ./gradlew :app:compileDebugKotlin; cd ..
```

For memory-sensitive units (3, 4, 9, 10), on the Redmi A3:
```powershell
adb shell dumpsys meminfo com.navisense.app | Select-String "TOTAL PSS"
```

> **Tooling note:** This is a Flutter project, so `flutter`/`dart` are the canonical tools for dependency resolution, analysis, testing, and builds. If you write standalone JS/TS helper scripts (for example a Remote Config publishing script or a secret scanner), run them with **`bun`** (`bun install`, `bun run <file>`), never `npm`/`npx`. Typecheck with `bun run build` before running them.

Report the actual output (pass/fail counts) in your summary. **Never claim a command passed without running it.**

## 5.4 Hard Bans (Instant Rejection)

| Ban | Why |
|---|---|
| Any Web dependency or code: `dart:js_interop`, `dart:html`, `package:web`, `idb_shim`, IndexedDB, `ReCaptchaEnterpriseProvider`, `kIsWeb` branches, conditional `dart.library.*` exports, `web/` folder | Android-only scope |
| iOS/macOS/Windows/Linux platform code or folders added to the build | Android-only scope |
| Hard-coded API keys, tokens, Firebase config values, or service-account JSON anywhere in source, tests, or context | Zero-trust |
| Committing `lib/firebase_options.dart`, `android/app/google-services.json`, `secrets.json`, keystores | Zero-trust |
| Calling Gemini REST endpoints directly (bypassing Firebase AI Logic / App Check) | Security + compliance |
| Deprecated `FirebaseAIOnDevice.checkStatus()` / `download()` standalone APIs | Use `GenerativeModel.OnDeviceExtension` |
| Storing `CameraImage` / `InputImage` / image bytes in state or fields | OOM on 3 GB devices |
| Creating ML Kit detectors per frame | Memory + latency |
| Cloud calls without a timeout, or catch blocks that swallow errors silently | Never-silent guarantee |
| New dependencies not listed in `2-architecture.md` §2.1 without human approval | Footprint + license review |
| Changing formatter golden strings or telemetry pill labels without updating context | Demo + test integrity |

## 5.5 Memory Budget Rules (Redmi A3, 3 GB, Android Go)

- Total PSS **< 150 MB** steady state. Peak during a Tier 2 request < 170 MB.
- Any unit adding a dependency must report APK size delta (`flutter build apk --analyze-size --target-platform android-arm64`). Budget: release APK ≤ 60 MB arm64.
- Prefer streaming from files over loading bytes (`DeviceFileSource`, `File.openRead`).
- No image decoding in Dart at full resolution. Downscaling happens natively (see `4-code-standards.md` §4.5.7).
- Use `const` widgets aggressively. Avoid `Opacity` over the camera preview (use `ColorFiltered` or an overlay `Container` with alpha).

## 5.6 Updating Progress After Each Unit

After verification passes:

1. In `context/6-progress-tracker.md`:
   - Flip the unit's checklist items to `[x] DONE` (or `[~] IN_PROGRESS` with a blocker note).
   - Add a line to the **Changelog** table: date (WAT), unit, summary, verification result.
2. If you discovered a contract change (for example a real SDK method name differs), update `context/2-architecture.md` **in the same commit** and note it in the changelog with `CONTRACT CHANGE:` prefix.
3. Commit: `unit-N: <summary>` including the tracker update.
4. Final message to the human, ≤ 15 lines: what changed, files touched, verification output, next unit.

## 5.7 When Blocked

- **SDK/API mismatch:** search the official Firebase / ML Kit / Flutter docs, apply the documented API, record a `CONTRACT CHANGE`. Never invent an API.
- **Missing credentials** (`google-services.json`, debug token): stop and ask the human. Never create fake config files that would be committed.
- **Device-only behavior** (AICore, Play Integrity): implement behind the interface, unit-test with mocks, and list the manual device test steps for the human.
- **Network or permission errors from the environment:** report them. Do not work around sandbox, proxy, or credential restrictions.

## 5.8 Definition of Done (every unit)

- [ ] Only the unit's target files changed (plus justified wiring)
- [ ] `dart format` clean, `flutter analyze` 0 issues, `flutter test` green
- [ ] Debug APK builds
- [ ] Acceptance criteria in `units.md` demonstrably met
- [ ] No banned items (§5.4)
- [ ] Progress tracker + changelog updated
