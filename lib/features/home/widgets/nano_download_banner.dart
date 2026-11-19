import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navisense/core/theme/navi_colors.dart';
import 'package:navisense/core/utils/clock.dart';
import 'package:navisense/features/ai_orchestrator/nano_bridge.dart';
import 'package:navisense/features/home/settings_screen.dart';

/// Non-blocking AICore Gemini Nano 4 download banner (`3-ui-context.md` §3.6).
///
/// Shown ONLY when `getStatus()` returns `downloadable` or `downloading`.
/// Never shown on `unavailable` devices (e.g. Redmi A3).
final class NanoDownloadBanner extends ConsumerStatefulWidget {
  /// Creates a [NanoDownloadBanner].
  const NanoDownloadBanner({super.key});

  @override
  ConsumerState<NanoDownloadBanner> createState() => _NanoDownloadBannerState();
}

final class _NanoDownloadBannerState extends ConsumerState<NanoDownloadBanner> {
  bool _hiddenThisSession = false;
  int? _lastAnnouncedQuarter;
  String? _errorText;
  bool _startingDownload = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<NanoStatus>>(nanoStatusProvider, (
      AsyncValue<NanoStatus>? previous,
      AsyncValue<NanoStatus> next,
    ) {
      final prevVal = previous?.value;
      final nextVal = next.value;
      if (prevVal != null &&
          prevVal != NanoStatus.available &&
          nextVal == NanoStatus.available) {
        _announce(context, 'On-device AI ready.');
      }
    });

    ref.listen<AsyncValue<NanoDownloadProgress>>(nanoDownloadProgressProvider, (
      AsyncValue<NanoDownloadProgress>? previous,
      AsyncValue<NanoDownloadProgress> next,
    ) {
      if (next.hasError) {
        if (!mounted) return;
        setState(() {
          _startingDownload = false;
          _errorText =
              'On-device AI download paused. NaviSense will keep using cloud '
              'and offline guidance.';
        });
        _announce(context, _errorText!);
        return;
      }

      final progress = next.value;
      if (progress == null) return;
      if (_errorText != null && mounted) {
        setState(() => _errorText = null);
      }

      final percent = progress.percent;
      if (percent != null) {
        final quarter = (percent ~/ 25) * 25;
        if (_lastAnnouncedQuarter != quarter) {
          _lastAnnouncedQuarter = quarter;
          _announce(
            context,
            'Downloading on-device AI: $percent percent. '
            'NaviSense works normally meanwhile.',
          );
        }
      }
    });

    if (_hiddenThisSession) return const SizedBox.shrink();

    final statusAsync = ref.watch(nanoStatusProvider);
    final status = statusAsync.value;
    if (status != NanoStatus.downloadable &&
        status != NanoStatus.downloading &&
        _errorText == null) {
      return const SizedBox.shrink();
    }

    final settings = ref.watch(settingsProvider);
    final nowMs = ref.read(clockProvider).nowMs();
    if (status == NanoStatus.downloadable &&
        !_startingDownload &&
        _errorText == null &&
        settings.isNanoBannerDismissedAt(nowMs)) {
      return const SizedBox.shrink();
    }

    final progress = ref.watch(nanoDownloadProgressProvider).value;
    final isDownloading = status == NanoStatus.downloading || _startingDownload;

    final message = _bannerMessage(
      isDownloading: isDownloading,
      percent: progress?.percent,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        container: true,
        sortKey: const OrdinalSortKey(1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NaviColors.navySurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _errorText != null
                  ? NaviColors.errorRed
                  : NaviColors.goldAntique,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: <Widget>[
                    Icon(
                      _errorText != null
                          ? Icons.warning_amber_rounded
                          : isDownloading
                              ? Icons.downloading_rounded
                              : Icons.offline_bolt_rounded,
                      color: _errorText != null
                          ? NaviColors.errorRed
                          : NaviColors.goldAntique,
                      size: 24,
                    ),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: NaviColors.cream,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isDownloading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: progress?.percent != null
                          ? progress!.percent! / 100.0
                          : null,
                      backgroundColor: NaviColors.navyDeep,
                      color: NaviColors.goldAntique,
                    ),
                  ),
                _BannerActions(
                  isError: _errorText != null,
                  isDownloading: isDownloading,
                  onDownloadOrRetry: _startDownload,
                  onNotNow: () {
                    unawaited(
                      ref
                          .read(settingsProvider.notifier)
                          .dismissNanoBannerForSevenDays(),
                    );
                  },
                  onHide: () => setState(() => _hiddenThisSession = true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _bannerMessage({required bool isDownloading, required int? percent}) {
    final err = _errorText;
    if (err != null) return err;
    if (isDownloading) {
      final pctText = percent != null ? ': $percent%' : '';
      return 'Downloading on-device AI$pctText. NaviSense works normally meanwhile.';
    }
    return 'Faster on-device AI is available for your phone. Download now? '
        'About 1 GB on Wi-Fi recommended.';
  }

  Future<void> _startDownload() async {
    setState(() {
      _errorText = null;
      _startingDownload = true;
    });
    try {
      await ref.read(nanoBridgeProvider).startDownload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _startingDownload = false;
        _errorText =
            'On-device AI download paused. NaviSense will keep using cloud '
            'and offline guidance.';
      });
    }
  }

  void _announce(BuildContext context, String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    // WHY: Throttled accessibility update per §3.6.
    unawaited(
      SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
    );
  }
}

final class _BannerActions extends StatelessWidget {
  const _BannerActions({
    required this.isError,
    required this.isDownloading,
    required this.onDownloadOrRetry,
    required this.onNotNow,
    required this.onHide,
  });

  final bool isError;
  final bool isDownloading;
  final VoidCallback onDownloadOrRetry;
  final VoidCallback onNotNow;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    if (isError) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: <Widget>[
          OutlinedButton(
            onPressed: onDownloadOrRetry,
            child: const Text('Retry'),
          ),
          TextButton(onPressed: onHide, child: const Text('Hide')),
        ],
      );
    }

    if (isDownloading) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: onHide, child: const Text('Hide')),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton(
          onPressed: onDownloadOrRetry,
          child: const Text('Download'),
        ),
        TextButton(onPressed: onNotNow, child: const Text('Not now')),
      ],
    );
  }
}
