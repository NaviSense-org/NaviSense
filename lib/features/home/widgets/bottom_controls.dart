import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:navisense/core/theme/navi_colors.dart';

/// Three discrete >= 72x72dp bottom-edge controls (`3-ui-context.md` §3.2).
final class BottomControls extends StatelessWidget {
  /// Creates [BottomControls].
  const BottomControls({
    super.key,
    required this.onRepeat,
    required this.onReadText,
    required this.onOpenSettings,
  });

  /// Replays the last guidance response.
  final VoidCallback onRepeat;

  /// Triggers OCR-prioritized text reading.
  final VoidCallback onReadText;

  /// Opens [SettingsScreen].
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: <Widget>[
        Expanded(
          child: _ControlTile(
            sortOrder: 3,
            icon: Icons.replay_rounded,
            label: 'Repeat',
            semanticsLabel: 'Repeat last guidance',
            onPressed: onRepeat,
          ),
        ),
        Expanded(
          child: _ControlTile(
            sortOrder: 4,
            icon: Icons.document_scanner_rounded,
            label: 'Read',
            semanticsLabel: 'Read text',
            onPressed: onReadText,
          ),
        ),
        Expanded(
          child: _ControlTile(
            sortOrder: 5,
            icon: Icons.settings_rounded,
            label: 'Settings',
            semanticsLabel: 'Settings',
            onPressed: onOpenSettings,
          ),
        ),
      ],
    );
  }
}

final class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.sortOrder,
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final double sortOrder;
  final IconData icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      sortKey: OrdinalSortKey(sortOrder),
      button: true,
      label: semanticsLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 72, minHeight: 76),
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(72, 76),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            backgroundColor: NaviColors.navySurface.withValues(alpha: 0.94),
            foregroundColor: NaviColors.cream,
            side: const BorderSide(color: NaviColors.goldAntique, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: <Widget>[
              Icon(icon, color: NaviColors.cream, size: 26),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: NaviColors.cream,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
