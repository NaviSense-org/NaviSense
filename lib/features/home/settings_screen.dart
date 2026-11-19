import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/voice/local_tts_service.dart';
import 'package:navisense/features/voice/wav_cache.dart';
import 'package:path_provider/path_provider.dart';

/// Persisted user and judge preferences (`3-ui-context.md` §3.6, §3.8, §3.9).
@immutable
final class SettingsState {
  /// Creates a [SettingsState].
  const SettingsState({
    this.speechRate = LocalTtsService.defaultRate,
    this.hapticsEnabled = true,
    this.announceInferenceTier = false,
    this.judgeMode = false,
    this.nanoBannerDismissedUntilMs,
    this.onboardingCompleted = false,
  });

  /// Restores [SettingsState] from decoded JSON map.
  factory SettingsState.fromJson(Map<String, Object?> json) {
    final rateRaw = json['speechRate'];
    final rate = rateRaw is num
        ? rateRaw.toDouble().clamp(
              LocalTtsService.minRate,
              LocalTtsService.maxRate,
            )
        : LocalTtsService.defaultRate;
    final haptics = json['hapticsEnabled'];
    final announce = json['announceInferenceTier'];
    final judge = json['judgeMode'];
    final dismissedUntil = json['nanoBannerDismissedUntilMs'];
    final onboarded = json['onboardingCompleted'];

    return SettingsState(
      speechRate: rate,
      hapticsEnabled: haptics is bool ? haptics : true,
      announceInferenceTier: announce is bool ? announce : false,
      judgeMode: judge is bool ? judge : false,
      nanoBannerDismissedUntilMs: dismissedUntil is int ? dismissedUntil : null,
      onboardingCompleted: onboarded is bool ? onboarded : false,
    );
  }

  /// Local TTS speech rate in `[0.30, 0.70]`.
  final double speechRate;

  /// Whether tactile tier haptics are enabled.
  final bool hapticsEnabled;

  /// Whether TalkBack focuses and announces the telemetry pill.
  final bool announceInferenceTier;

  /// Whether the secondary latency/template line shows inside the pill.
  final bool judgeMode;

  /// Epoch milliseconds until which "Not now" suppresses the Nano banner (7 days).
  final int? nanoBannerDismissedUntilMs;

  /// Whether the first-launch spoken onboarding has played.
  final bool onboardingCompleted;

  /// Returns `true` if the user dismissed the Nano banner within the last 7 days.
  bool isNanoBannerDismissedAt(int nowMs) {
    final until = nanoBannerDismissedUntilMs;
    return until != null && nowMs < until;
  }

  /// Returns a copy with updated fields.
  SettingsState copyWith({
    double? speechRate,
    bool? hapticsEnabled,
    bool? announceInferenceTier,
    bool? judgeMode,
    int? Function()? nanoBannerDismissedUntilMs,
    bool? onboardingCompleted,
  }) {
    return SettingsState(
      speechRate: speechRate ?? this.speechRate,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      announceInferenceTier:
          announceInferenceTier ?? this.announceInferenceTier,
      judgeMode: judgeMode ?? this.judgeMode,
      nanoBannerDismissedUntilMs: nanoBannerDismissedUntilMs != null
          ? nanoBannerDismissedUntilMs()
          : this.nanoBannerDismissedUntilMs,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  /// Serializes this state for `navisense_settings.json`.
  Map<String, Object?> toJson() => <String, Object?>{
        'speechRate': speechRate,
        'hapticsEnabled': hapticsEnabled,
        'announceInferenceTier': announceInferenceTier,
        'judgeMode': judgeMode,
        'nanoBannerDismissedUntilMs': nanoBannerDismissedUntilMs,
        'onboardingCompleted': onboardingCompleted,
      };
}

/// Abstracts settings JSON file persistence for unit/widget testing.
abstract interface class SettingsStorage {
  /// Loads persisted settings or returns `null` when none exist.
  Future<SettingsState?> load();

  /// Saves [state] atomically to disk.
  Future<void> save(SettingsState state);
}

/// Default JSON file storage in app documents (`navisense_settings.json`).
final class JsonFileSettingsStorage implements SettingsStorage {
  /// Creates a [JsonFileSettingsStorage].
  const JsonFileSettingsStorage({Future<File> Function()? fileProvider})
      : _fileProvider = fileProvider ?? _defaultFileProvider;

  static const String _fileName = 'navisense_settings.json';
  final Future<File> Function() _fileProvider;

  static Future<File> _defaultFileProvider() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  @override
  Future<SettingsState?> load() async {
    try {
      final file = await _fileProvider();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return SettingsState.fromJson(decoded);
      }
      if (decoded is Map) {
        return SettingsState.fromJson(
          decoded.map(
            (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
          ),
        );
      }
      return null;
    } on MissingPluginException {
      return null;
    } catch (e, st) {
      log(
        'Failed to read settings file; using defaults',
        name: 'navisense.settings',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  @override
  Future<void> save(SettingsState state) async {
    try {
      final file = await _fileProvider();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
      await tmp.rename(file.path);
    } on MissingPluginException {
      // Ignore in widget tests without path_provider channels.
    } catch (e, st) {
      log(
        'Failed to persist settings file',
        name: 'navisense.settings',
        error: e,
        stackTrace: st,
      );
    }
  }
}

/// Provides [SettingsStorage] (overridable in tests).
final settingsStorageProvider = Provider<SettingsStorage>(
  (ref) => const JsonFileSettingsStorage(),
);

/// Provides persisted [SettingsState] via [SettingsNotifier].
final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// Manages persisted user and judge settings.
final class SettingsNotifier extends Notifier<SettingsState> {
  static const int _sevenDaysMs = 7 * 24 * 60 * 60 * 1000;

  @override
  SettingsState build() {
    unawaited(_hydrate());
    return const SettingsState();
  }

  Future<void> _hydrate() async {
    final loaded = await ref.read(settingsStorageProvider).load();
    if (!ref.mounted || loaded == null) return;
    state = loaded;
    await ref.read(localTtsServiceProvider).setRate(loaded.speechRate);
  }

  /// Updates the local TTS speech rate (`0.30`–`0.70`) and persists it.
  Future<void> setSpeechRate(double rate) async {
    final clamped = rate.clamp(
      LocalTtsService.minRate,
      LocalTtsService.maxRate,
    );
    state = state.copyWith(speechRate: clamped);
    await ref.read(localTtsServiceProvider).setRate(clamped);
    await ref.read(settingsStorageProvider).save(state);
  }

  /// Enables or disables tactile tier haptics.
  Future<void> setHapticsEnabled(bool enabled) async {
    state = state.copyWith(hapticsEnabled: enabled);
    await ref.read(settingsStorageProvider).save(state);
  }

  /// Enables or disables TalkBack focus/announcements on the telemetry pill.
  Future<void> setAnnounceInferenceTier(bool enabled) async {
    state = state.copyWith(announceInferenceTier: enabled);
    await ref.read(settingsStorageProvider).save(state);
  }

  /// Shows or hides the secondary latency/template telemetry detail line.
  Future<void> setJudgeMode(bool enabled) async {
    state = state.copyWith(judgeMode: enabled);
    await ref.read(settingsStorageProvider).save(state);
  }

  /// Suppresses the AICore download banner for 7 days (`3-ui-context.md` §3.6).
  Future<void> dismissNanoBannerForSevenDays() async {
    final until = ref.read(clockProvider).nowMs() + _sevenDaysMs;
    state = state.copyWith(nanoBannerDismissedUntilMs: () => until);
    await ref.read(settingsStorageProvider).save(state);
  }

  /// Marks first-launch onboarding complete.
  Future<void> markOnboardingCompleted() async {
    if (state.onboardingCompleted) return;
    state = state.copyWith(onboardingCompleted: true);
    await ref.read(settingsStorageProvider).save(state);
  }
}

/// High-contrast, TalkBack-first settings screen (`3-ui-context.md` §3.9).
final class SettingsScreen extends ConsumerWidget {
  /// Creates a [SettingsScreen].
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 72),
          tooltip: 'Back to camera',
          icon: const Icon(Icons.arrow_back, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        leadingWidth: 72,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: <Widget>[
            _SpeechRateTile(
              rate: settings.speechRate,
              onChanged: (double v) => unawaited(notifier.setSpeechRate(v)),
            ),
            const Divider(color: NaviColors.goldAntique, height: 1),
            _SettingsSwitchRow(
              title: 'Haptics',
              subtitle: 'Feel distinct pulse patterns per AI tier',
              value: settings.hapticsEnabled,
              onChanged: (bool v) => unawaited(notifier.setHapticsEnabled(v)),
            ),
            const Divider(color: NaviColors.goldAntique, height: 1),
            _SettingsSwitchRow(
              title: 'Announce inference tier',
              subtitle: 'Allow TalkBack to focus and read the tier pill',
              value: settings.announceInferenceTier,
              onChanged: (bool v) =>
                  unawaited(notifier.setAnnounceInferenceTier(v)),
            ),
            const Divider(color: NaviColors.goldAntique, height: 1),
            _SettingsSwitchRow(
              title: 'Judge mode',
              subtitle: 'Show latency and prompt template details on the pill',
              value: settings.judgeMode,
              onChanged: (bool v) => unawaited(notifier.setJudgeMode(v)),
            ),
            const Divider(color: NaviColors.goldAntique, height: 1),
            _ActionSettingsRow(
              title: 'Clear audio cache',
              subtitle: 'Delete cached spoken WAV responses on this device',
              icon: Icons.delete_outline,
              onTap: () => unawaited(_confirmClearCache(context, ref)),
            ),
            const Divider(color: NaviColors.goldAntique, height: 1),
            _ActionSettingsRow(
              title: 'Licenses',
              subtitle: 'Open-source software notices and Apache 2.0 license',
              icon: Icons.description_outlined,
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'NaviSense',
                  applicationVersion: '1.0.0',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Clear audio cache?'),
          content: const Text(
            'Cached high-fidelity voice responses will be removed until '
            'synthesized online again.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(wavCacheProvider).clear();
    if (context.mounted) {
      await ref.read(localTtsServiceProvider).speak('Audio cache cleared.');
    }
  }
}

final class _SpeechRateTile extends StatelessWidget {
  const _SpeechRateTile({required this.rate, required this.onChanged});

  final double rate;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final formatted = rate.toStringAsFixed(2);
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: <Widget>[
              Text(
                'Speech rate: $formatted',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Semantics(
                label: 'Speech rate $formatted',
                child: Slider(
                  value: rate,
                  min: LocalTtsService.minRate,
                  max: LocalTtsService.maxRate,
                  divisions: 8,
                  label: formatted,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              spacing: 12,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ActionSettingsRow extends StatelessWidget {
  const _ActionSettingsRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                spacing: 12,
                children: <Widget>[
                  Icon(icon, color: NaviColors.goldAntique, size: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: <Widget>[
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
