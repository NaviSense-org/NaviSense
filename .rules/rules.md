# Flutter Deterministic Blueprint
## (Generalized — Project-Agnostic)

> Clean, scalable, predictable Flutter architecture. Given any screen name you can predict where its pod, logic, actions and widgets live. Drop into any Flutter project; `init_blueprint.md` = the portable kit (components, pod templates, infrastructure) that makes these rules concrete.
> Reader = AI model first, human second. Notation: `✓` do · `✗` never · `→` use / leads to · `⇒` implies · `≤`/`≥` limits · `·` separates items. Paths are relative to `lib/` unless noted. Project names in examples (spaces, canvases) are illustrations; map them to your domain.

---

## Contents
0 Hard rules (strict) · 1 Philosophy & precedence · 2 Folders · 3 app/ · 4 core/ · 5 data/ · 6 network/ · 7 features/ · 8 shared/ · 9 Widgets · 10 Pods (Riverpod) · 11 Routing & overriders · 12 Architecture formula · 13 Docs & comments · 14 Performance & heavy work · 15 Naming · 16 Stack & AI checklist · 17 UX principles · 18 Desktop & adaptive · 19 Feedback, errors & copy · 20 Offline, caching & sync · 21 Session hygiene · 22 Platform interops & permissions · 23 Transfers (uploads / downloads) · 24 AI features · 25 Testing & previews · 26 Workflow & hand-off docs

---

## 0. Hard rules (strict — override everything below)
- **Builds**: ✗ `flutter build …` / `flutter run` / `xcodebuild` / `./gradlew assemble*` / compiling `pod install` unless the user asks in that request. Verify with `fvm flutter analyze` + `fvm flutter test`; native code → type-check only (`xcrun swiftc -typecheck`). If only a build can prove it: say so + give the exact command.
- **Codegen**: ✗ `build_runner` without asking (it deletes committed `.g.dart`). Asset changes → hand-edit the generated `assets.gen.dart` in flutter_gen's format.
- **Apple packaging**: Swift Package Manager only (`flutter: config: enable-swift-package-manager: true`); ✗ `ios/Podfile` / CocoaPods anywhere in the tree. A plugin with no `Package.swift` is vendored under `packages/` with its own manifest before it's added as a path dependency.
- **Formatting**: ✗ `dart format` on existing files/dirs (80-col default reflows long-line code, bloats files). Match surrounding line length (~120).
- **Heavy work off the UI thread**: decoding, thumbnails (PDF raster, image downscale), hashing, big JSON/HTML parsing, text extraction, base64 of files → `Isolate.run` / `compute` / plugin worker. UI only awaits; results cached (memory + disk) so each is produced once.
- **Reuse app components**: every button/card/sheet/dialog comes from `shared/components/` (§8, init_blueprint). ✗ new `InkWell`/`Material`/`IconButton`/`TextButton`/`OutlinedButton` buttons. Grep before building; extend a shared widget rather than hand-roll.
- **Phone layouts never change for desktop work** (§18).
- **Git**: ✗ commit / stash / reset / checkout unless asked; the tree may hold the user's uncommitted work.
- **UI never calls the network** (§6, §12 Rule 1).
- **User-facing errors** only via `UserMessage.from(e)` — ✗ `e.toString()` in UI or state (§19).

## 1. Core Philosophy & Precedence
- **Deterministic architecture**: from a screen name, its pod/logic/actions/widgets location is predictable.
- **Pragmatic clean architecture**: UI → Actions/Logic → Pods → UI. No ceremony layers.
- **Structural precedence**: before creating a pattern, find an existing one and mirror it. New pattern only when none applies, then apply it everywhere.
- **AI tooling**: inspect project structure before generating files; follow established patterns strictly.
- **User comfort first**: user convenience beats developer shortcuts in every decision (architecture, state, caching, networking, UI). Details §17.

### 1.1 User comfort pillars (summary; full list §17)
1. Unobtrusive feedback: top-anchored swipeable toasts (`AppToast`); ✗ blocking dialogs for non-destructive things; ✗ covering bottom nav/FAB/thumb zone.
2. Offline-first: never block creation offline; persist locally at once; queue sync; say "saved on this device".
3. Instant hydration: cache on first frame (< 16 ms), refresh quietly; ✗ blank screens / full-screen spinners over known data.
4. Context preserved: scroll position (`PageStorageKey`), drafts, tabs, launch restore; scroll-to-top aids on long lists.
5. Tactile & smooth: `ScaleClickWrapper` press feedback; heavy work in isolates; 60/120 fps.

## 2. Folder Structure
```
lib/
├── app/        ← bootstrap, routes (app/routes), engines, app-wide pods (app/pods), previews
├── core/       ← infra, zero feature deps: base/, constants/, interops/, network/, utils/
├── data/       ← persistence drivers & repos (drift/, hive/, const/)
├── features/   ← vertical slices
├── network/    ← Api.instance, endpoint groups, models (requests/ responses/), AuthSession
└── shared/     ← cross-feature components/ and theme/
```
Internal shape of any non-title folder: `src/` (impl) · `models/` (optional; `in/`,`out/` or `requests/`,`responses/`) · `extra/` (misc) · `<folder>.dart` barrel.

## 3. lib/app
- `ui/app.dart`: root `App` (MaterialApp.router; builder hosts system-UI region, desktop theme scope, global listeners like share intake / notification hub mount).
- `pods/`: app-wide non-autoDispose pods: theme/font prefs, device prefs (`AppPrefsPod`: behaviour + network policy + layout toggles), `NetworkStatusPod` (connectivity).
- `routes/`: `app_router.dart` (GoRouter + `rootNavigatorKey`), `routes.dart` (typed `Routes` enum, `part of`), `core/` (`auto_route.dart` wrapper, `route_extra_codec.dart`, `route_stack_recorder.dart`, `launch_restore.dart`), `src/` (one file per route group exporting `final xRoute`).
- `engines/`: startup — every engine awaited before `runApp` goes through `StartupWatchdog.optional`/`.required` (never a bare `await`): optional engines (Firebase) skip on timeout/error, required ones (storage, network init) bound the launch (slow screen at ~1.5 s, error screen with a working Retry at ~25 s) — never a blank window; `session_hooks.dart` (§21).
- `previews/`: `@AppPreview` widgets per domain (`<domain>_previews.dart`, desktop in `desktop_previews.dart`); fixtures in `previews/src/*_fixtures.dart` (§25).
- `assets/`: generated `assets.gen.dart` / `fonts.gen.dart` (hand-edited, §0).

## 4. lib/core
### 4.1 core/base
- Provider access extensions (`extension_on_provider.dart`):
```dart
X.me.watch(ref) / X.me.read(ref)      // WidgetRef
X.me.watchX(ref) / X.me.readX(ref)    // Ref (inside pods)
X.me.not(ref) / X.me.notX(ref)        // notifier
context.inCallerScope(child)          // re-scope modal content (§9.8)
```
- `custom_notifiers.dart`: `KIntNotifier`, `KDoubleNotifier`, `KStringNotifier`, `KBoolNotifier(toggle)`, `KSomeNotifier<T>`, `KWatchNotifier<T>` (stream), `KSomeAsyncNotifier<T>`, **`KCachedNotifier<In,Out>`** = AsyncNotifier persisted as JSON in a DB kv table (Drift `kv_cache`), serialized writes, memory-only under `FLUTTER_TEST`, never fatal. Static `readCache/writeCache/deleteCache/clearAll` = the per-user key–value cache every pod uses for hydration.
- Mixins: `TextEditingControllerFactoryMixin` (`useTextEditingController`, `resetControllers`, `disposeControllers` in `ref.onDispose`) · `PaginationHandler<T>` (`PagingController`, `fetchPage`, `getNextPageKey`, `refresh`, `@mustCallSuper dispose`), wrapped by **`AppPagingController`** (`fetchNextPage()` ignored while the last page is in error; `retry()` is the only way past a failure — wire Retry buttons to it, never `fetchNextPage()`; debounced offline→online retry, once).
- `AppSyncBus` + `SyncEvent(entity, action, id, spaceId, payload)` — cross-pod change feed (§20). `StudyActivityBus` — same shape, for reporting study activity (reading/lesson seconds, page edits, practice/review rounds) from wherever it happens, without that code knowing about streaks or any other consumer.
- Extensions (`extensions/src/`): `s.orNull`, `s.isBlank`, `s.initials` · `n.count('member')`, `n.capped()` · `d.progress01`, `d.percent` (never 100 before done) · `dur.humanize`, `dur.clock` · `dt.timeAgo()`, `AppDateFormat.pattern()` (cached), `.time(ctx,t)` (24 h aware), `.lastAccessed` · `formatBytes`.
### 4.2 core/constants
`Spacing` (xxs4 xs8 sm12 md16 lg24 xl32 xxl48 xxxl64 + `num.inRow/inColumn`) · `AppRadius` (xs6 sm8 md12 lg16 xl20 pill) · enums · typedefs · `app_constants` · `allowed_extensions` · barrel via `part`/`part of`. ✗ magic numbers for spacing/radii.
`AppFeatures` — one bool switch per parked/toggleable feature (e.g. `notebooks`); gates every entry point app-wide (nav, creation menus, pickers) instead of deleting code, documented inline with what each switch gates.
### 4.3 core/interops
Every platform plugin sits behind **driver seam + static facade** (template in init_blueprint §P4): `abstract interface class XDriver` · `PluginXDriver` · facade `XInterop` with `@visibleForTesting static set driver`, `_guard(fallback)` (never throws), init after first frame, test-safe default (no plugin channels under `FLUTTER_TEST`). Examples: notifications (+ push), calendar, connectivity (`AppNetwork: unmetered|metered|offline|unknown`), permissions, audio, haptics (`HapticsInterop`), secure storage (`SecureStore`: keychain/keystore → OS login-keychain fallback → memory for the run, never throws, moves a value back to the primary store once it works again), home-screen widgets (`HomeWidgetsInterop` + `HomeWidgetSyncPod`: one versioned JSON payload; native widgets never call the network and compute their own day rollover with the same rules as the Dart side).
### 4.4 core/network
`OfflineTaskHandler` (persisted offline queue, retry timer only while queued, `isOnline()`). `RequestLoopGuard` (Dio interceptor, first in the chain): the same failing request (no response) 3× within 10 s is answered at once from the same offline failure until it ages out or the network changes — the backstop against a retry loop, never a substitute for fixing the loop at its source (§P2, init_blueprint).
### 4.5 core/utils
`misc/result.dart` (`Result<T>`: `success/error`, `tryRun*`, `isSuccess`, `value`, `message`) · `misc/user_message.dart` (`UserMessage.from(e, fallback:)`) · `misc/session_reset.dart` · `misc/sync_throttle.dart` · `misc/bounded_parallel.dart` (`mapWithConcurrency(items, task, limit: 4)`) · `misc/cover_placeholder.dart` · `nav_utils.dart` (root-context helpers for code without a context).

## 5. lib/data
- `drift/`: global DB (kv cache) + per-user DB (`UserDatabase`, closed on sign-out); tables / models / repos (`AbstractOneToManyRepo`).
- `hive/`: typed keys (`HiveKeys`), device prefs read synchronously.
- Repos/logic ✗ throw → return `Result<T>`. Remote access lives in pods or `*Remote` provider gateways (§25), never in repos called from UI.

## 6. lib/network
- `Api.instance` groups endpoints (`Api.instance.auth`, `.spaces`, `.ai`, `.uploads`…); built on `kickin_network` (see `network_rules.md`).
- Requests declared once: `late final _x = KPostRequest(this, path:, decoder:)`; call sites `.copyWith(data:, headers: addAuthAndJsonTypeHeaders(), cancelToken:, onSendProgress:).catchErrorOnSendResult()`.
- Envelope: `Future<ApiResult<T?>>`; decoders tolerate `{data: …}` and bare payloads (`castDataFromRaw`), return null on non-2xx.
- `AuthSession.instance` (tokens, `headersFor(url)` for authed media), `core_api.dart` (isolated refresh client).
- **Boundary**: `screens/ widgets/ actions/` ✗ import `network/api.dart` for calls (models may be imported). Calls happen in pods / logic.
- Missing backend endpoints: assume a sensible contract, implement fully against it with graceful fallback (hide feature, on-device fallback, keep local), and append the contract to the hand-off doc (§26).

## 7. lib/features
Self-contained vertical slices; subfolders optional.
### 7.1 Grouping
1. Standalone: `features/<feature>/`.
2. Grouped domain: `features/<group>/<feature>/` (each child complete: `ui/ pods/ logic/ models/`).
3. Grouping is one level only: `features/<group>/<feature>/`; a feature may not contain another feature. A grouped feature child must be a complete vertical slice, not a parent for more features.
4. `main` = root shell + tabs only: `features/main/{main,home,calendar,library,space,…}/…`; widgets shared across tabs → `main/others/`. ✗ nest distinct flows in `main`.
### 7.2 Layers
```
features/<f>/
├── models/      ← domain + presentation models (+ Args for routes)
├── logic/       ← pure Dart, no BuildContext/ref, returns Result<T>, never throws
├── pods/        ← notifiers + states (+ ext_on_<pod>_<topic>.dart parts)
└── ui/
    ├── actions/ ← imperative flows (context + ref): dialogs, sheets, toasts, nav, haptics
    ├── screens/ ← <Name>View (const, zero init code)
    ├── widgets/ ← focused widgets (+ src/, modals/, tab sub-regions §9.5)
    ├── models/  ← UI-only models
    └── desktop/ ← <f>_desktop_view.dart, widgets/, widgets/src/ (§18)
```
### 7.3 Layer rules
- `screens/`: suffix `View`; `const XView({super.key})`; args via route overrider (§11).
- `actions/`: `abstract final class XActions` with static methods. Multi-step UI logic lives here so widgets stay declarative.
- `logic/`: orchestration, validation, transforms, pure policies (easy unit tests). ✗ `BuildContext`/`ref`.
- `pods/`: state + side effects (network, storage). ✗ widgets.

## 8. lib/shared
`components/` (buttons, cards, dialogs, sheets, inputs, indicators, badges, avatars, images, layout, state, animated, app_bar, desktop, painters, typography, pages) · `theme/` (tokens, typography, fonts, system UI). A widget is **shared** when used by ≥ 2 features and holds no feature knowledge; promote from feature → shared only then. Full catalog + usage rules → **init_blueprint.md §C**. Must-knows:
- Text → `AppText` (+ `textTheme.<role>`), ✗ raw `Text`/`TextStyle(fontSize, fontWeight)` pairs.
- Press → `ScaleClickWrapper` (`onPressed`, range from `PressScalePolicy` below, `boxShadow:` for elevation, hover grow, right-click = long-press; null handlers ⇒ static) · `InstantPressScale` for toolbars · `AppCircleIconButton` (tooltip required) · `AppButton` (`enabled`, `isLoading`).
- Images → `AdaptiveImage` **only** (network/asset/file auto-detected or `imageType`, auth headers for API host, shimmer, fallback, `cacheWidth`; `AdaptiveImage.memory(bytes)` (null → `fallback`); `AdaptiveImage.decoded(uiImage)` for a picture you decoded and own (null → `placeholder`, you dispose it)). Shimmer/placeholder until the first frame, 200 ms fade; a memory-cache hit paints at once (no shimmer/fade); `gaplessPlayback` keeps the old picture while a new source loads. ✗ `Image.*`, `RawImage`, raw `CachedNetworkImage`, `*Image(` providers, `DecorationImage` in feature code; textures → `DustTexture`. ✗ a plain `SizedBox`/empty-box `placeholder` for a picture that loads from somewhere (network/file) — use `ImageShimmer`; bundled fallback art that decodes within a frame (e.g. a logo mark used as a cover fallback) may keep a plain sized box instead, so it doesn't shimmer forever in tests/offline. Stay instant on re-show: one `cacheWidth` per picture kind everywhere it's shown (Library covers: `LibraryCoverPage.decodeWidth`) · `cacheKey` for per-request signed links (`ContentPolicyLogic.remoteKey`) · never change a shown file's mtime (file images key on path + mtime + size) · fallback art goes in `placeholder`/`fallback`, not painted underneath.
- Previews in cards/tiles/pickers show the real picture (page/space cover, file first page, image thumb, link badge) with the tinted brand fallback; an icon only when nothing previewable exists.
- Glass / blur → one switch: every frosted surface reads `AppBlur` (`layout/app_blur.dart`): `BlurAware(builder: (ctx, solid, child))` → `BackdropFilter(enabled: !solid)` + `AppBlur.fill(tint, solid)` (near-opaque when solid); plain blur → `AppBackdropBlur(sigma:)`. ✗ `enabled: !kIsWeb`, ✗ raw `BackdropFilter`. Solid = Settings → Appearance → "Blur effects" off (default on web) or a native view showing on macOS. Previews/tests: `AppBlurOverride(solid:)`.
- Popups → the app barrier (light dim + faint σ 3 page blur easing with the route; blur off → deeper dim) via the shared launchers; custom route bodies use `AppModalRoutes.sheet/dialog/general` or `with AppBarrierRoute`. The frosting belongs to the popup itself: menus / popup cards / dialogs draw `AppGlassSurface(color:)` (translucent tint + backdrop blur + hairline + shadow), sheets `AppSheetGlass`. ✗ opaque popup cards.
- Card elevation → `AppCardShadow.of(context)` (`pure.cardShadow`: soft lift on light, none on dark or inside sheets; `raised: true` on hover). Tappable cards pass it to `ScaleClickWrapper(boxShadow:)` (the wrapper clips its child, so a shadow inside never shows). Horizontal card rows clip sideways only (`HorizontalOnlyClipper` + `ListView(clipBehavior: Clip.none)`).
- See-all pages → `SeeAllScaffold` (`pages/see_all_scaffold.dart`): `PureAppBar` over a `CustomScrollView` + the page's slivers + `SeeAllBottomBar` (search + filter at the bottom). ✗ Column + app bar + top search field.
- Press scale → `PressScalePolicy` (single source, applied inside `ScaleClickWrapper`/`InstantPressScale`): phones (1.0, 1.1), desktops (1.0, 1.07), mobile browsers (1.0, 1.0) with no press delay. Call sites never branch on platform; opt-out `keepScaleOnMobileWeb: true`.
- Markdown → `AppMarkdown(text, density:, selectable:, fitContent:)` (block, for bubbles/lists) / `AppMarkdown.document(text)` (scrolling) / `MarkdownCodeBlock(code:, language:)` from `components/markdown/` (`flutter_markdown_plus`; parsed once, memoised, ≥ 20k chars parsed in an isolate). Decide with `MarkdownDetectLogic.looksLikeMarkdown`.
- Secondary sheet actions → `AppSheetQuickActions` (horizontal row of icon + short label under the sheet header; important actions stay tiles; danger stays a danger section).
- Opening a file in another app → `SystemOpenInterop` (outbound; `OpenWithInterop` is inbound "Open with AppName"), always after `FileDownloadPod`.
- Feedback → `AppToast` · `AppDialog.confirm/info/prompt` · `AppInlineAlert` · `AppEmptyState(.loadError)`.
- Sheets → `AppBottomSheet.show` (+ header/section/tile/footer/glass) — becomes a draggable floating dialog on wide desktop.
- Menus → `AppAnchoredMenu` / `AnchoredPopup` (placement via `AnchoredMenuPlacement`); long popups (> ~7 actions) → `AppActionMenu<T>` instead (§9.8).
- Paged lists → `PagedSliverGrid`/`PagedSliverList` (or `AppPagedSheetSection`) fed by `PaginationHandler`/`AppPagingController`, or `PagedView.of(items, hasMore:, isLoading:, error:)` for a pod-held list; footer → `AppPagedFooter.loading()` / `.failed(error:, onRetry:)`. ✗ hand-rolled `page`/`hasMore`/`isLoadingMore` flags; Retry calls `retryPage()`/`controller.retry()`, never `fetchNextPage()`.
- Step-by-step flows (onboarding-style) → `AppStepSwitcher` + `AppStepProgress` + `AppStepHeader` with a pinned Back/Continue bar; optional steps show "Skip" only while empty.
- Notification dots/pills → `AppNotificationBadge` (`shared/components/badges/`), never a bare `Badge` — it paints the background-colour ring that separates the mark from its icon.
- Colours → `Theme.of(context).pure.*` tokens; hairlines `pure.outline(base,a)` / `pure.separator(a)` / `pure.grabber(a)` (✗ `border.withValues(alpha:)` on translucent ink — light theme breaks).
- Fonts → Albert Sans is the bundled default (variable upright + italic in `assets/fonts/`, first frame / offline / web / PDF fallback); every other font goes through `RuntimeFonts` (`theme/src/typography/`): every face of a family under **one** family name (variable `[wght]` files where Google ships them; `FontWeight` drives the axis), fetched backend-first by `FontFetcher` (`{apiBase}/assets/fonts/{sha256}.ttf`, pinned upstream fallback), SHA-256-checked off the UI thread, cached on device. ✗ `google_fonts` styles (per-variant family names fake bold/italic on every `copyWith`).
- Status marks: a card shows **at most one** check mark (Library: the verified seal); other states read as words or their own icon.

## 9. Widget Architecture & Parameter Rules
### 9.1 Size & decomposition
- Widget/screen files ≈ ≤ 100 LOC, **≤ 200 hard tolerance** (action classes and pods may be longer but split by topic). Over it → extract.
- Decompose into private classes at file bottom (`_Header`, `_Body`, `_Trailing`); ✗ `Widget _buildX()` helper methods.
- Reusable/significant → own file; tiny single-parent → private class.
### 9.2 Direct state selection
- Sub-widgets that need pod data are `Consumer*` and read the pod directly (✗ drilling). Exceptions: shared components, list item data.
- One field → `ref.watch(P.me.select((s) => s.x))`. Several fields of one source → one `select` returning a record `(a, b)` or one watch. ✗ several selects on the same state.
- `select` stable values (records, primitives, memoized lists); a `select` that builds a new list each emit rebuilds each emit — fine for small lists, otherwise memoize on state (`late final` fields).
### 9.3 Parameters: data · props · callbacks
| Bucket | Content | Grouping |
|---|---|---|
| `data` | entity/content | always named `data` (a model) |
| props | layout/style flags | 1–2 → named params · ≥ 3 → `XProps` |
| callbacks | handlers | 1–3 → named params · ≥ 4 → `XCallbacks` |
Nullable handler ⇒ hide the action / no press feedback.
### 9.4 Canonical entities
One canonical entity per domain; projections via `toX()`/views; sheets/dialogs take the canonical entity (✗ naked field unpacking at call site); ✗ callbacks inside data models.
### 9.5 Tab sub-folders
`widgets/<tab>/{above/, body/{src/, sections/}, bottom/, src/}` — only the regions that exist.
### 9.6 Specialist widgets
`ColoredBox`, `SizedBox`, `Padding`, `DecoratedBox`, `Align` over `Container`; `spacing:` on Row/Column over manual gaps.
### 9.7 Previews
Every new screen, sheet, dialog or major widget → `@AppPreview` + registration (§25). Previews are self-contained (pod overrides, fixtures, no network).
### 9.8 Sheets, dialogs, popups
- Size to content: `Column(min)` → pinned header → `Flexible(scroll body)` → safe bottom; route `useSafeArea: true`; cap at safe-top + 8; keyboard lifts; drag-to-dismiss. ✗ fixed heights/fractions. `expandable: true` (DraggableScrollableSheet) only for long browsable lists.
- Launch only via `AppBottomSheet.show` / `AppDialog.*` / `AppAnchoredMenu` / `AnchoredPopup` (✗ raw `showDialog`/`showModalBottomSheet`).
- **Modals keep the caller's provider scope**: modal routes sit above route-level overrides ⇒ capture `ProviderScope.containerOf(context, listen: false)` before showing (shared launchers do) or `context.inCallerScope(child)`; capture before any `pop`.
- Primary action → `AppSheetFooter` (pinned, `enabled` for validation, `isLoading`).
- Structure: `AppBottomSheetHeader` · `AppBottomSheetSection` (captioned, `.danger` last) · `AppBottomSheetTile` · `AppSheetDivider` · surface `AppSheetGlass` (cards inside use `AppSheetGlass.cardFill`).
- Wide desktop: the same sheet renders as a floating dialog (`DesktopSheetDialog`), **draggable** by its grip strip and by headers wrapped in `SheetDragRegion`; stays ≥ 96 px on screen; double-click grip re-centres; position remembered per session. Sheet parts check `SheetPresentation.isDialogOf(ctx)` (e.g. hide grab pill).
- Sheets that lead to another sheet/dialog pop first, then run the follow-up.
- Long popups (> ~7 actions) → `AppActionMenu<T>`: hand-off actions in a quick grid up top (icon + short label, 1–4 in a row), the actions people come for as rows, rarely-used ones folded under "More options" (unfolds in place, only when it hides ≥ 3), danger last; desktop grid cells get tooltips. Single-choice picks in any popup close it at once; only explicit multi-select or a live-preview appearance editor stays open.
### 9.9 Loading states
Skeleton (`Skeletonizer`) only on first load with nothing cached, around the specific content (✗ whole screens). Cached data ⇒ render it + a small "syncing" indicator.

## 10. Riverpod State Pattern (Pod Pattern)
### 10.1 Feature pod
```dart
final _featureProvider = NotifierProvider.autoDispose<FeaturePod, FeatureState>(
  () => FeaturePod.create(arg: const FeatureArgs()), name: 'FeaturePod');

class FeaturePod extends Notifier<FeatureState> {
  static final me = _featureProvider;
  final FeatureArgs arg;
  FeaturePod.create({required this.arg});

  @override
  FeatureState build() {
    Future.microtask(_load);                       // cache first, then refresh
    return FeatureState.initial(arg);
  }
}
```
Access: `FeaturePod.me.watch(ref)` / `.not(ref)` (UI) · `.watchX(ref)` / `.notX(ref)` (pods).
### 10.2 Conventions
- Immutable state classes (`<f>_state.dart`), hand-written `copyWith` (+ `toMap/fromMap` when persisted); nullable clears via `T? Function()? field` (preferred) — don't mix idioms in one class. `dart_mappable` is optional, not required.
- Value equality → `Equatable` (`props` in field order); hand-written `==`/`hashCode` only when intentionally partial (id-only), identity-based or a measured hot path — with a one-line comment why.
- `autoDispose` for screen/feature pods; plain `NotifierProvider` only for app-wide services (prefs, theme, network status, upload/download trackers, notification hub, registries). Global pods holding user data reset on the session event (§21).
- `.family` for per-key state (per page/source conversation).
- Scale: > ~200 LOC of bodies → `part 'ext_on_<pod>_<topic>.dart'` as **mixins** `mixin _TopicOps on Notifier<S>` (applied with `with`, may chain `on _OtherOps`), declaring needed members abstractly (`Map<String,X> get _map;`). ✗ extensions for mutating parts (they can't touch protected `state` cleanly).
- Sub-pod aggregation: `static final child = ChildPod.me;` on the parent.
- After **every** `await` in a pod: `if (!ref.mounted) return;`.
- Fire-and-forget explicit: `unawaited(f)` / `.ignore()`. Concurrency: record `.wait` for independent futures (unwrap `ParallelWaitError`), `mapWithConcurrency` for bulk.
- ✗ read `state` in `onDispose` (Riverpod 3 asserts) → mirror pending values in fields and flush them there.
- ✗ return a future from a `whenComplete` callback that is the same future (self-await deadlock): use a block body `whenComplete(() { _running.remove(id); })`.
- Test seams: constructor-injected interfaces (`X.create({Uploader? uploader})`), `@visibleForTesting static debugX` hooks, `*Remote` provider gateways (§25).
- A mutation in a pod a sheet only `read`s (scoped / autoDispose) holds `ref.keepAlive()` until it settles and emits its `SyncEvent` (incl. rollback) even after unmount, returning an honest result even when `!ref.mounted`; work that must finish after its screen is gone (background confirms, §17) lives in a method that touches no pod state (static / id-based) or on an app-wide pod. Capture form values before the first `await`. A details-only pod patches its own cache key, never the entity's full cache.
- Editors: `readOnly` is derived from page access in one place (the controller setter), never by code that swaps controllers. Content added from another screen pulses once (`showAdded`); the sustained `reveal` ring is the assistant's only.
### 10.3 4-step guardrail (async mutations)
```dart
Future<void> save() async {
  if (state.isSaving || !_valid) return;                        // 1 guard
  state = state.copyWith(isSaving: true, error: () => null);    // 2 loading
  final r = await _logic.save(state.draft);                     // 3 execute (Result)
  if (!ref.mounted) return;
  state = r.isSuccess                                            // 4 handle
      ? state.copyWith(isSaving: false, data: r.value)
      : state.copyWith(isSaving: false, error: () => r.message); // UserMessage-backed
}
```
Mutations that the UI must react to return `bool` / `Result` / an outcome enum (e.g. `pinned | limitReached | failed`) so actions choose the right toast. Optimistic updates roll back on failure. Emit a `SyncEvent` after success (§20).

## 11. Routing & The Overrider Pattern
Router = go_router wrapped by the local `AutoRoute` class (not the auto_route package). Widgets navigate via `Routes.x.push/go/pushReplacement(context, extra:, id:)`; ✗ import go_router in widgets.
### Zero UI initialization
Views are `const`; ✗ `initState` arg reading / post-frame provider init / constructor args. Route args enter the pod through `overrider` → route-level `ProviderScope`, disposed with the route.
```dart
final detailRoute = AutoRoute<DetailArgs>.route(
  Routes.detail,
  parentNavigatorKey: rootNavigatorKey,
  desktopPopupWidth: DesktopWidths.narrow,          // optional floating page on wide desktop
  overrider: (_, state, [extra, id]) => [
    DetailPod.me.overrideWith(() => DetailPod.create(arg: extra ?? DetailArgs(id: id ?? state.uri.queryParameters['id']))),
  ],
  builder: (context, state) => AdaptiveLayout(
    compact: (_) => const DetailView(),
    wide: DesktopPlatform.isTarget ? (_) => const DetailDesktopView() : null,   // §18
  ),
);
```
- Patterns: A multi-arg `…Args` model · B single primitive/entity · C shell initial tab.
- Detail routes accept the entity (instant hydration) **and** an `id` / query params (deep links, restore); the overrider `switch`es over every accepted extra shape into one `Args`.
- **Every route extra type** ⇒ `toMap()/fromMap()` + entry in `RouteExtraCodec._entries` + round-trip test; unknown extras are dropped and the route falls back to `id`/query.
- Deep links (`https://<host>/…`) → `GoRoute` redirects into typed routes; links carry highlight/focus targets (`…Args(highlight:)`).
- Launch restore (`RouteStackRecorder` + `LaunchRestore`): stack saved ~600 ms after navigation and on any non-resumed lifecycle; restored ≤ 12 h, ≤ 5 deep, allowlisted; launches from share/notification call `LaunchRestore.claim()`.
- "Go to parent": pop back if it's in the stack, else `pushReplacement`.
- Wrappers that must sit above a view (e.g. a desktop side-panel host the view's actions look up) are applied in the route builder, guarded by `DesktopPlatform.isTarget`.

## 12. The Architecture Formula (Quick Rules)
1. **API calls never in the UI** — pods / logic only.
2. **Imperative UI flows in `ui/actions/`** — widgets delegate.
3. **Pod scaling via `ext_on_<pod>_<topic>.dart` mixin parts.**
4. **Extract shared shells** when 2+ widgets share layout/styling.
5. **Overrider for zero UI init**; views are const.
6. **Previews for every new whole widget**, registered in the preview tests (light + dark, desktop when relevant).
7. **User comfort first** (§17): offline creation, instant hydration, top toasts, preserved context, no dead ends.
8. **Emit sync events after mutations; wipe per-user state on sign-out** (§20, §21).
9. **Desktop adds, never changes phone** (§18).
10. **No fabricated data; blank hides its line; errors via `UserMessage`** (§19).

## 13. Code Documentation Standards
- Class doc: what it is + the non-obvious *why* (platform quirk, perf, policy). ✗ restating code.
- Simple function: one `///` line. Complex function with helpers: 3-line `// ====` separator + one `///` line; private helpers follow before the next separator.
- Grouped-block comments above meaningful 2–10-line blocks; ✗ line-by-line narration.
- Pod section headers: `/// ====…` `INITIALIZATION & LIFECYCLE` · `PUBLIC API` / `PUBLIC MUTATIONS` · `RUNNING` etc.
- Match the surrounding comment density.

## 14. Performance & Heavy Work
- `const` everywhere possible; targeted rebuilds (§9.2); `RepaintBoundary` around heavy paint; lazy lists/slivers; ✗ shrink-wrapped `ListView` inside scroll views (use `Column` or slivers/`SliverMainAxisGroup`).
- Images decode near shown size (`cacheWidth` = px × dpr; ×2 for cover crops; hero = screen width; `FilterQuality.low` for avatars).
- Heavy work in isolates (§0) + cache: memory → disk → produce; keyed work queues (de-dup, newest first, ≤ 2 concurrent, dropped when no caller). ✗ download a remote file just to preview it.
- Bounded reads (`readHead`) for previews; cached `DateFormat`s and decorations; no live `BackdropFilter` per list item.
- Progress callbacks from transfers are throttled (≥ 2 % step or 250 ms) before touching state.
- Stored absolute file paths are re-rooted on read (iOS container UUID changes per install).
- `ValueNotifier` + `ValueListenableBuilder` for purely local UI state; `setState` only in small leaf widgets.
- Document exports (PDF) run in `Isolate.run` over plain data (no widgets / `dart:ui` types); pictures are decoded by the engine before the isolate. Fonts embedded in exports are static faces (a variable file embeds at its default instance).

## 15. Naming Conventions
| Concern | Convention | Example |
|---|---|---|
| Screens | `View` | `ProfileView`, `QuizView` |
| Desktop screens | `DesktopView` | `SpaceDetailDesktopView` |
| Pods / state | `Pod` / `State` | `TransfersPod`, `TransfersState` |
| Pod parts | `ext_on_<pod>_<topic>.dart`, `mixin _TopicOps` | `ext_on_file_upload_pod_network.dart` |
| Actions / logic | `Actions` / `Logic` (abstract final, static) | `TransferActions`, `TransferPolicyLogic` |
| Repos / API groups | `Repo` / `Api` | `UserRepo`, `AiApi` |
| Backend models | `Data` | `SpaceData` |
| UI models | `Model` (only when ≥ 3 fields diverge from `Data`) | `SpacePageModel` |
| Requests / responses | `Request` / `Response` / `Data` | `TranscribeRequest`, `TranscriptionData` |
| Route args | `Args` | `TransfersArgs`, `StudySetArgs` |
| Seams / platform | `Driver`, `Interop`, `…er` interface + `Default…` | `ConnectivityDriver`, `FileUploader` |
| Props / callbacks | `Props` / `Callbacks` | `TransferTileCallbacks` |
| Enums | PascalCase | `TransferWait` |
| Files | snake_case | `transfer_tile.dart` |
| Private | `_` prefix | `_Header`, `_featureProvider` |
Data vs Model: consume backend `Data` directly when it fits; create a UI `Model` only when ≥ 3 fields diverge or presentation logic is needed.

## 16. Stack & AI Checklist
| Concern | Package / approach |
|---|---|
| State | `flutter_riverpod` 3 (`Notifier`, `AsyncNotifier`, families) |
| Navigation | `go_router` via local `AutoRoute` + `Routes` enum + `RouteExtraCodec` |
| Network | `kickin_network` (Dio) |
| Persistence | Drift (kv cache + per-user DB) · Hive (`kickin_storage`) for sync device prefs · `flutter_secure_storage` for secrets |
| Models | hand-written immutable + `copyWith` + `toMap/fromMap` (`dart_mappable` optional) |
| Assets | `flutter_gen` output (hand-edited, §0) |
| Pagination | `infinite_scroll_pagination` via `PaginationHandler` / `AppPagingController`; a pod-held list → `PagedView.of` |
| Animation | implicit animations, `flutter_animate` |
| Toasts | own `AppToast` overlay |
| Images | `cached_network_image` behind `AdaptiveImage` |
| Connectivity | `connectivity_plus` behind `ConnectivityInterop` |
| Notifications | `flutter_local_notifications` + FCM behind interops |
**AI contribution checklist**: 1 verify precedent (grep shared/, sibling features) · 2 pod pattern + overrider · 3 ≤ 200 LOC widgets, private sub-widgets · 4 tokens only (`pure`, `Spacing`, `AppRadius`, text roles) · 5 no drilling · 6 comfort (§17) · 7 desktop parity where it applies (§18) · 8 previews + tests · 9 `analyze` clean + tests green, no builds · 10 update hand-off docs (§26).

## 17. UX Principles (portable)
**Speed & continuity**
- Cache on first frame, refresh behind it; pass the tapped entity to the next screen for instant render.
- Skeletons only on true first load; afterwards a small syncing indicator.
- Waiting is honest and staged: real bytes, the stage, a "why" line after ~5 s, a way forward (viewers: `ViewerLoadingStatus`); ✗ bare spinners / "Opening…". If one engine is slow and another can show the content now, offer (or, for local copies, switch to) it for this open only.
- Throttle automatic refreshes (~2 min per screen); pull-to-refresh always refreshes.
- Resume where the user left off (launch restore; per-document view state: last page, viewport, tone).
- Screens stay in sync without manual refresh (sync bus).
**Offline & errors**
- Offline ≠ empty: "Couldn't load … · Retry" only when nothing is cached; failed retry keeps the error.
- Never block creation offline; say where the work is ("Saved on this device", "Offline · saved on device").
- One calm sentence + next step for errors; optimistic updates roll back visibly.
**Feedback**
- Top toasts, one at a time, swipe to dismiss; never over bottom nav / thumb actions.
- Reversible single deletes: act now + Undo toast. Destructive / bulk / irreversible: confirm (name the object, red button); the dialog closes at once and the work finishes in the background behind a progress toast (`AppBackgroundTask`) that resolves into success or a calm failure with Retry — never dangling (timeout, pod alive until settled, rollback, `SyncEvent`, §10.2). Wait in the dialog only when the result decides the next screen (sign-out everywhere, delete account, create-and-open).
- A "discard changes?" confirm appears only when there are changes (e.g. non-empty undo history), never on a plain open-and-close.
- Pinned primary actions in sheets, disabled (not hidden) until valid.
- Deep-linked items scroll into view and pulse once.
- Press feedback is physical (scale); disabled things don't pretend. Haptics subtle and semantic (selection tick, success, error).
- Background arrivals announce themselves with a way to jump there ("Added … · Show").
**Covers & placeholders**
- Items without an image get the **brand mark tinted on a soft wash of the same tint** (e.g. `AppNameCoverFallback`), not a generic icon or grey box; document cards show the real first page taking most of the card.
- Library tall cards stand the real first page as a book on a wash tinted per category (`LibraryBookStage`): one check (the verified seal) on the book itself, controls (⋯, selection) on the stage around it, never over the book.
- "Changed since you looked": a violet ringed dot (`AppNotificationMark`, `pure.accentViolet`) for edits and a violet xs "New" label for additions — one mark per card, nothing older than 14 days, never for the user's own work, through a `ChangeMarkLogic` / `SeenPod`-style read-state pod.
**Honesty**
- ✗ fabricated/placeholder data as real (initials, codes, counts); unknown ⇒ not rendered.
- Missing optional field removes its line/badge; counts are real totals; progress never 100 % early; times human ("Just now").
- UI only hides/disables what users can't do — the server is the authority.
**Guidance**
- Every empty state says what goes here + the action to fill it; hints show once, then get out of the way.
- Hide actions that can't apply now (✗ dead ends); auto-name from content instead of prompting.
**Visual hierarchy & contrast (Refactoring UI)**
- Weight over size: establish typographic hierarchy using font weights (`FontWeight.w500`–`w700`) and color contrast (`pure.primary`, `pure.textPrimary`, `pure.textMuted`) rather than dramatic font size jumps. Avoid thin, washed-out low-contrast body or metadata.
- Purposeful color accents: avoid drab monochrome gray/white cards. Anchor domain entities (spaces, active tags, locations, key indicators) with `pure.primary` or dedicated semantic accents (e.g. `FileVisuals`, `pure.accentViolet`), so cards never feel flat or apathetic.
- Depth via elevation and surface tints: use borderless card depth with subtle shadows (`AppCardShadow`) and soft surface tints rather than harsh high-contrast borders everywhere.
- Distillation & scannability (Impeccable `distill`): never repeat metadata already surfaced by an overlay badge or cover image (e.g. omit file extensions from card subtitles when an overlaid glass badge already identifies it).
- Optical balance & rhythm: align icons with text baselines, maintain consistent vertical padding scales (`Spacing`), and preserve breathing room.
**Affordances, signifiers & heuristics (Norman & Krug)**
- Self-evident affordances: every tappable surface must signal interactivity through clear signifiers and tactile spring feedback (`ScaleClickWrapper`).
- The Trunk Test (Krug): an observer glancing at any card or screen must instantly answer: *Where am I? What is this item? What is its type? What action can I take next?*
- Slips vs. mistakes: prevent slips through confirmation sheets for destructive batch actions, but keep non-destructive single actions immediate with undo toasts.
**Impeccable design engineering passes**
- `typeset`: enforce consistent line heights, tabular figures (`FontFeature.tabularFigures()`) on dates and counters, explicit weights.
- `harden`: rigorous text overflow handling (`maxLines: 1, overflow: TextOverflow.ellipsis`), defensive layout constraints, empty/error/loading parity across all form factors.
**Permissions & interruptions**
- Ask only in context after an in-app explanation; "Not now" remembered; if the OS won't prompt, route to Settings.
- Background notices respect user toggles; **one grouped notification per activity** (e.g. one uploads notice for the whole batch), never one per item; notifications carry the useful actions (e.g. Wait for Wi-Fi · Cancel · View).
**Data costs**
- Big transfers follow a user network policy (default **Wi-Fi only**); waiting is visible ("Waiting for Wi-Fi") with a one-tap override ("Use mobile data"); offline waits instead of failing; explicit user actions ask before spending data.
**Layout & ergonomics**
- Sheets size to content, respect status bar + keyboard; popups open by their trigger and never leave the safe area.
- Search/filters within thumb reach; scrolling dismisses the keyboard; touch targets ≥ 40–44 px; icon-only controls have tooltips.
- Frosted surfaces keep context; light dims; status-bar icons match the background; light and dark designed separately.
- Immersive/focus modes always leave a visible way out (exit pill, Esc).
**Privacy**
- Sign-out wipes user data (caches, files, thumbnails, AI history, notifications), keeps device prefs; sensitive content blocks screenshots.

## 18. Desktop & Adaptive
- Code: `features/<f>/ui/desktop/{<f>_desktop_view.dart, widgets/, widgets/src/}`; shared primitives `shared/components/desktop/` (barrel `desktop.dart`).
- **Tree-shaking gate**: every reference to desktop-only code sits in a branch whose condition **starts with** `DesktopPlatform.isTarget` (`@pragma('vm:platform-const')`). ✗ via another getter.
- `isTarget` = build includes desktop · `isActive` = rendering on desktop now (tests default to Android ⇒ phone layout).
- Form factors (desktop only): compact < 600 · medium 600–1023 · expanded ≥ 1024. Phones/tablets always compact. Caps from `DesktopWidths` (page 880, narrow 640, sheet 560, dialog 440, form 480).
- Layout choice in the **route** (`AdaptiveLayout`), not inside views. Floating secondary pages: `AutoRoute(desktopPopupWidth:)` → `AdaptivePage` (Esc / click-outside closes).
- Desktop views reuse phone widgets inside `ReadableWidth` / `DesktopSplitScaffold` (narrowed `MediaQuery`); ✗ editing phone layouts.
- Side panels (e.g. an assistant docked beside a page at ≈ 45 % width, resizable 30–60 %, only when expanded) are hosts above the page that give it a narrowed `MediaQuery` and expose a scope the page's actions look up; below the breakpoint the same flow falls back to a sheet.
- Sheets → draggable floating dialogs (§9.8). Toasts → centred cards.
- Keyboard: one **shortcut registry** (`AppShortcut(key, shift:, alt:)` → `activator` ⌘ on Apple / Ctrl elsewhere, `label` "⌘⇧D" / "Ctrl+Shift+D", `tip` for tooltips only when desktop is active) grouped for a "Keyboard shortcuts" sheet (⌘/); screens bind via `AppShortcutBindings({shortcut: action})` (app-wide ones at the root, page ones on the page, only acting when the shell is ready). Esc closes / exits focus. Toggles toggle (second press of a tool / panel key turns it off).
- Right-click = long-press; copy says "Right-click" on desktop. Scrollbars only when `isActive`.
- **Contextual actions float by their target** on desktop (selection toolbar above the selection — flips below / clamps inside chrome insets, follows pan/zoom, hides while dragging or editing); right-click opens it at the pointer; right-click on empty space opens an anchored menu (`AppAnchoredMenu.showAt(rect)`) with "add here" actions. Phones keep bottom toolbars.
- Navigation aids that fit wide screens: Docs-style sidebars (sections left, comments right) that replace the compact controls while open, toggle from the same button / shortcut, remembered per device, shown only when the width fits both (fallback to sheets). These sidebars / docked panes are resizable by their inner edge (`DesktopPaneDivider` drag handle): min/max per pane, the page keeps ≥ 440 px, double-click resets, width remembered per device, written when the drag ends; layout follows the drag without easing, then eases again.
- Every screen a user reads in (pages, files, library books) hosts `SplitViewHost` on desktop, so "open X beside this" works the same everywhere; a page there opens in its real editor.
- A document has one editor at a time: a second place showing it (pane, window) shows it read-only with "Go to it" and edits again when the other closes; moving a page between places unmounts the old editor first (edits save on dispose).
- A desktop pane is its own `FocusScope`: clicking either side gives it the keyboard; Esc backs out of the focused side's own state first and closes the pane last. The docked AI panel belongs to the main page (AI asked from a pane opens the floating assistant).
- Drag content into docked panels (e.g. a section / selection into the AI panel) with a desktop-only draggable chip; the target frames itself while hovered.
- Outline / table-of-contents taps scroll the target under the chrome and pulse it once (reuse the deep-link highlight).
- Desktop previews `@AppPreview(desktop: true)` + desktop preview test (macOS override, 1440×900). Native window config (min size) is part of desktop work.
- Native windows remember size/position/maximized per platform (macOS `setFrameUsingName` **before** `setFrameAutosaveName`; Windows `window_placement.cpp` registry; Linux `~/.config/appName/window.ini`). Linux runner renders with Skia by default (`APPNAME_RENDERER=impeller` opts in; release builds ignore engine env switches).
- macOS/iOS Runner targets never set `ONLY_ACTIVE_ARCH = NO` for Debug (SwiftPM plugin products build the active arch only → explicit-module "Unable to find module dependency" on the other arch).
- macOS entitlements: restricted keys (`keychain-access-groups`, …) only in profile-signed builds; CI/ad-hoc builds sign with their own entitlements file holding none of them. App-group entitlements are team-prefixed (`$(TeamIdentifierPrefix)…`, no profile entry needed), never `group.`-prefixed. Widget extensions (WidgetKit) share their SwiftUI source between iOS and macOS and stay Swift Package Manager-only like the app (§0).

## 19. Feedback, Errors & Copy
- Transient → `AppToast.success/info/warning/error(ctx, msg, {title, actionLabel, onAction})`. Persistent → `AppInlineAlert`. Empty/failed → `AppEmptyState` / `.loadError`.
- Errors: `UserMessage.from(e, fallback: '…')` (maps timeouts, offline, 401/403/404/5xx, platform & file errors; passes readable backend `{message}`; rejects technical text).
- Toasts that act later (Undo) capture the `ProviderContainer`, not the `WidgetRef`; show them while the row's context is mounted.
- Copy: sentence case, calm, second person, no jargon; product nouns single-sourced from enums/labels; one sentence + next step.
- ✗ fabricated data; blank strings hide their line (`s.orNull`, `MetaDotSeparated`, `MetaRow`, `AppBadge(label: null)`).

## 20. Offline, Caching & Sync
- Hydration: pod `build()` returns initial state, `Future.microtask(_load)` reads `KCachedNotifier.readCache`, then refreshes if `SyncThrottle.shouldSync(key)` (force on pull-to-refresh).
- Error fields only when load failed AND nothing cached. Keep best-known values when a payload omits them.
- **Sync bus**: after every successful mutation `AppSyncBus.instance.emit(SyncEvent(entity, action, id:, spaceId:, payload:))`; listeners subscribe in `build`, cancel in `onDispose`, patch from `payload` instead of refetching. Delivery is async ⇒ tests `await pumpEventQueue()`.
- Offline creation → `OfflineTaskHandler.queueTask`; UI never waits on the network to create.
- Documents: local save debounced (~400 ms), server save later (~2 s); sync decision logic pure and tested; status line "Saved · 2m ago" / "Offline · saved on device".
- In-flight edits are folded into state before teardown; ✗ provider writes during widget teardown.
- Background work that outlives its screen (uploads, transcriptions, downloads) lives in **global pods keyed by item id**, persisted per user; the item's widget listens and writes the result back (post-frame) when it lands — also after the page was closed and reopened (`FileUploadListener`, `VoiceTranscriptListener` pattern).
- Settings-backed look properties (page font, paper…) are stored as "own pick or null = follows Settings" and resolved live from `AppPrefsPod`; ✗ snapshotting the default into the item. Device-only additions to synced collections live in a separate overlay pod keyed by the collection id, never in the synced model (files under app support per user + session hook).
- A server reply never erases what the device sent: merge an echoed entity with the local copy for fields the server dropped (anchors, mentions, …) until the contract is fixed — never let the echo overwrite data the device knows is right.
- Anything a signed-out user chooses for the account being created (profile photo, invite code, …) is staged on the device under device keys and applied once that account's first session exists — never lost to an email-verification / sign-up gap.
- Prefetching a document ahead of need never goes through the normal write path (that's a local edit): build it off the UI thread and store it with a raw-write helper that isn't counted as a change; skip copies with unsynced local edits; re-check freshness right before writing; background prefetch is Wi-Fi-only, one at a time, throttled.

## 21. Session Hygiene
- `SessionReset.run()` on sign-out / account switch: clear Hive except device keys → `KCachedNotifier.clearAll()` → `SyncThrottle.reset()` → registered hooks → emit `SyncEvent(session, deleted)`. Never throws.
- Register every per-user static cache / file dir / DB as a hook and every device pref key in `app/engines/session_hooks.dart` (e.g. downloaded files dir, thumbnails, AI history, drive auth).
- Global pods with user data listen for the session event and reset (cancel transfers, clear maps). ✗ re-keying the root `ProviderScope`.

## 22. Platform Interops & Permissions
- Driver seam + facade (§4.3). Interops init after first frame; never throw; never prompt on cold start.
- Permissions: in-context pre-prompt (reason-specific copy) → OS prompt; "Not now" remembered; denied → Settings.
- Notifications: channels per kind (reminders, uploads, downloads, activity, general); stable ids via FNV-1a over keys in partitioned ranges (✗ `String.hashCode`); transfer channels silent/low; progress notices only for slow (> 3 s) or backgrounded work, ≤ 2 updates/s; a result notice only if progress was shown or the user was away; **one notice per activity** replaced in place.
- Notification buttons: categories registered up front (iOS/macOS) + Android actions; taps and buttons arrive as `AppNoticeResponse(payload, actionId)`; buttons pressed in the background are delivered in a background isolate and forwarded to the app isolate through an `IsolateNameServer` port; buttons that open the app also route like a tap.
- Haptics via a named interop; accessibility: tooltips, semantics on composite visuals.
- Capability gates (e.g. the "Blur effects" default) use generic measured signals (Android media performance class / RAM / cores; desktop RAM, cores, Linux base clock) plus a one-time runtime frame-timing check; the user's explicit choice always wins; ✗ chip/model name lists. Telling my devices apart → `DeviceIdentity` (install id kept across sign-out + readable name).

## 23. Transfers (uploads / downloads)
- Global trackers keyed by item (`FileUploadPod` by attachment id, `FileDownloadPod` by remote file key) own every transfer: statuses `waiting → running → done | failed | cancelled`, progress + total bytes, per-item network override (`TransferRoute: auto | anyNetwork | wifiOnly`), cancel tokens, pause/resume on network change, persistence (unfinished uploads resume after restart; finished ones cached so cards resolve their URL; download history per user).
- Policy is pure (`TransferPolicyLogic.blockFor(network, policy, route)`); default policy **Wi-Fi only**; offline waits.
- Uploads are resumable on every path (AppName `/uploads/sessions` chunks, Drive resumable sessions): session ids kept per upload id, server offset asked on resume. Waiting (Wi-Fi / connection) **pauses** and keeps the server session; Cancel / Remove / owner deleted drops it (server `DELETE`, `uploader.forget(id)`). Active sessions double as "uploading on my other devices". Downloads send `Accept-Encoding: identity`.
- "Cancel" (user) keeps a cancelled entry with Retry; "deleted card/page" cancels silently and discards late results.
- Every download goes through the tracker (viewer, asset "Download", share/save, media playback) so screens, lists and notices agree; explicit actions on data ask first.
- Surfaces: per-scope Uploads & Downloads screen (tabs, grouped In progress / Didn't finish / Done, bulk actions, wait banner) and the same screen for **all scopes** reachable globally (desktop rail icon with a live running-count badge / red dot on failure; a phone tab's action-button menu) · pending rows at the top of asset lists · download marks on rows · status lines on cards · one grouped notification per direction with actions.
- Ambient / automatic downloads nobody asked for (e.g. small files cached quietly on encounter) are tracked exactly like any other download but marked quiet, so they never show in the Uploads & downloads screen, a pending strip, or a notification; a real request for the same file always upgrades it to visible, never the reverse. Unknown size ⇒ skip any size-based rule — never parse a formatted size label or probe by downloading; a model's own best-known raw byte count must reach the field that drives the rule.
- **Streamed documents**: large remote PDFs open straight from their link with HTTP range requests (pdfrx `PdfViewer.uri(preferRangeAccess: true)`), pages fetched on demand; side sheets (pages, contents) share the open document; "Save offline" / share / open-in fetch the full copy through the download tracker, and a saved copy is preferred when present. Covers render page 1 the same way (range request, off the UI thread, cached) when the server sends no thumbnail.

## 24. AI Features
- Everything the AI reads is an `AiContextItem` (id, source, label, text, optional image PNG, audio attachments, reference link); a per-message budget (chars, ≤ 3 images, ≤ 2 recordings); local-only media encoded in an isolate.
- Sources expose a port (read all / selection / part, insert, reveal); inserts for closed sources are queued and drained when opened.
- Conversations are per-source families kept alive while their source is open; history saved on device per user (index + entries, isolate encode for big ones), searchable, filterable by kind; plain chats unlabelled, special kinds (quiz, flashcards) labelled and opened on their own screens; the assistant never auto-resumes a special kind as a chat.
- Voice memos: send the transcript when present, else the recording; "Transcribe" writes the transcript onto the memo (synced with the page).
- Study sets (quiz / flashcards) from the context: server first, deterministic on-device fallback marked as such; progress (best score, known cards) saved with the set.
- AI UI on wide desktop docks as a side panel (§18); on phones a frosted sheet.

## 25. Testing & Previews
- Unit-test pure logic/policies (placement, transfer policy, notice wording, sync decisions, codecs). Pod tests with `ProviderContainer` + overrides + fakes (`FakeUploader`, fake drivers); clear persisted keys in `setUp`.
- Seams: interfaces via `create({…})`, `@visibleForTesting static debugX` hooks, `*Remote` gateways, `FLUTTER_TEST` guards for plugins/fonts/DB.
- Previews: `@AppPreview(name, group, tablet?, desktop?)` → light + dark; register in `test/app/previews_test.dart` (desktop ones in `test/app/desktop_previews_test.dart`); preview pods overridden with fixed state; sheets/menus need a `Scaffold`/`Material` ancestor; panels docked beside a `Scaffold` bring their own `Material`.
- Record equality compares lists/sets by identity ⇒ assert collections separately.
- Futures handed out by test seams are created inside the test body (fake clock); a `Future.value` made in `setUp` resolves in real time.
- Visual checks: render previews to PNG with real fonts in a throwaway test, look, then delete it.

## 26. Workflow & Hand-off Docs
- Keep `analyze` clean and tests green after each item; report exact counts; say what couldn't be verified without a device/build.
- `.rules/cache/cache_progress.md`: append a round section (what, where, verification, follow-ups).
- `.rules/cache/backend_endpoint_requests.md`: **append** new/changed backend contracts as the next numbered section; ✗ rewrite/renumber.
- `.rules/my_tasks.md`: manual steps for the user (consoles, native setup, device checks).
- Dead or commented-out shared code: delete or revive deliberately; ✗ document it as standard.
