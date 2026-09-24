import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A button you must press and hold (default 3 seconds) to complete.
///
/// While [unlocked] is false it shows [lockedLabel] and ignores presses.
/// Screen readers can trigger completion with the standard long-press action.
class HoldToReadButton extends StatefulWidget {
  const HoldToReadButton({
    super.key,
    required this.unlocked,
    required this.lockedLabel,
    required this.onCompleted,
    this.holdDuration = const Duration(seconds: 3),
  });

  final bool unlocked;
  final String lockedLabel;
  final VoidCallback onCompleted;
  final Duration holdDuration;

  @override
  State<HoldToReadButton> createState() => _HoldToReadButtonState();
}

class _HoldToReadButtonState extends State<HoldToReadButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _complete();
  }

  void _complete() {
    if (_completed) return;
    _completed = true;
    HapticFeedback.mediumImpact();
    widget.onCompleted();
  }

  void _start() {
    if (!widget.unlocked || _completed) return;
    _controller.forward();
  }

  void _release() {
    if (_completed) return;
    _controller.animateBack(0, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = widget.unlocked;

    return Semantics(
      button: true,
      enabled: unlocked,
      label: unlocked ? 'Mark as read' : widget.lockedLabel,
      onLongPress: unlocked ? _complete : null,
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: (_) => _start(),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _controller.value;
              final holding = progress > 0;
              final label = !unlocked
                  ? widget.lockedLabel
                  : holding
                      ? 'Keep holding'
                      : 'Hold to mark as read';
              return ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  height: 60,
                  width: double.infinity,
                  color: unlocked ? Palette.paleDeep : Palette.line,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          heightFactor: 1,
                          child: const ColoredBox(color: Palette.deep),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!unlocked) ...[
                            const Icon(Icons.lock_outline,
                                size: 18, color: Palette.muted),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: !unlocked
                                  ? Palette.muted
                                  : progress > 0.55
                                      ? Colors.white
                                      : Palette.deep,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
