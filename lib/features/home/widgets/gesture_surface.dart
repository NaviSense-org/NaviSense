import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:navisense/features/camera/widgets/camera_preview_layer.dart';

/// Full-screen TalkBack-first touch surface (`3-ui-context.md` §3.2, §3.3).
///
/// Covers 100% of the viewport behind chrome so tapping anywhere triggers
/// guidance, long-pressing reads visible text, double-tapping repeats the last
/// result, and two-finger tapping stops speech.
final class GestureSurface extends StatefulWidget {
  /// Creates a [GestureSurface].
  const GestureSurface({
    super.key,
    required this.isAnalyzing,
    required this.onDescribe,
    required this.onReadText,
    required this.onRepeat,
    required this.onStop,
  });

  /// Reflects whether `AiOrchestrator` is actively analyzing a frame.
  final bool isAnalyzing;

  /// Triggered on single tap / TalkBack double-tap activate.
  final VoidCallback onDescribe;

  /// Triggered on long-press / TalkBack double-tap-and-hold.
  final VoidCallback onReadText;

  /// Triggered on double-tap / TalkBack custom action "Repeat last guidance".
  final VoidCallback onRepeat;

  /// Triggered on two-finger tap / TalkBack magic tap or "Stop speaking".
  final VoidCallback onStop;

  @override
  State<GestureSurface> createState() => _GestureSurfaceState();
}

final class _GestureSurfaceState extends State<GestureSurface> {
  final Set<int> _activePointers = <int>{};
  bool _twoFingerTriggered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      sortKey: const OrdinalSortKey(2),
      label: 'NaviSense camera. Double tap to describe your surroundings.',
      hint: 'Double tap and hold to read text.',
      value: widget.isAnalyzing ? 'Analyzing…' : null,
      onTap: widget.onDescribe,
      onLongPress: widget.onReadText,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        const CustomSemanticsAction(label: 'Repeat last guidance'):
            widget.onRepeat,
        const CustomSemanticsAction(label: 'Stop speaking'): widget.onStop,
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent event) {
          _activePointers.add(event.pointer);
          if (_activePointers.length >= 2 && !_twoFingerTriggered) {
            _twoFingerTriggered = true;
            widget.onStop();
          }
        },
        onPointerUp: (PointerUpEvent event) {
          _activePointers.remove(event.pointer);
          if (_activePointers.isEmpty) {
            _twoFingerTriggered = false;
          }
        },
        onPointerCancel: (PointerCancelEvent event) {
          _activePointers.remove(event.pointer);
          if (_activePointers.isEmpty) {
            _twoFingerTriggered = false;
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () {
            if (!_twoFingerTriggered) widget.onDescribe();
          },
          onLongPress: widget.onReadText,
          onDoubleTap: widget.onRepeat,
          child: const CameraPreviewLayer(),
        ),
      ),
    );
  }
}
