import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Gives touch-driven tap controls a subtle impact across all app routes.
class TapHaptics extends StatefulWidget {
  const TapHaptics({required this.child, super.key});

  final Widget child;

  @override
  State<TapHaptics> createState() => _TapHapticsState();
}

class _TapHapticsState extends State<TapHaptics> {
  final Map<int, Offset> _presses = {};

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;

    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      event.position,
      event.viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderSemanticsAnnotations) continue;
      final config = SemanticsConfiguration();
      target.describeSemanticsConfiguration(config);
      if (config.onTap != null && config.isEnabled != false) {
        _presses[event.pointer] = event.position;
        return;
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final press = _presses.remove(event.pointer);
    if (press == null) return;
    if ((event.position - press).distance <= kTouchSlop) {
      HapticFeedback.lightImpact();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _presses.remove(event.pointer);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    onPointerUp: _onPointerUp,
    onPointerCancel: _onPointerCancel,
    child: widget.child,
  );
}
