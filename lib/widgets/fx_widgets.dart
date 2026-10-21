// lib/widgets/fx_widgets.dart
// Small, dependency-free effect widgets. All of them read Fx.level, so the
// Full / Reduced / Off setting and the phone's animation setting apply
// everywhere without each screen having to care.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../fx.dart';
import '../theme.dart';

// ---------------------------------------------------------------- count up

/// Lets a widget wait until its screen is actually in view before playing an
/// effect. Home sits underneath the decree screen after a read, so a change
/// to the streak or saves happens while Home is covered. Without this the
/// effect plays out of sight. [runWhenShown] runs the action now if the screen
/// is showing, otherwise right after it comes back into view (once the screen
/// on top has slid away).
mixin _WhenShown<T extends StatefulWidget> on State<T> {
  VoidCallback? _pendingAction;
  Timer? _shownTimer;

  bool get _screenShown => ModalRoute.of(context)?.isCurrent ?? true;

  void runWhenShown(VoidCallback action) {
    if (_screenShown) {
      _pendingAction = null;
      action();
    } else {
      _pendingAction = action;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final action = _pendingAction;
    if (action == null || !_screenShown) return;
    _pendingAction = null;
    _shownTimer?.cancel();
    // Wait for the page that was on top to finish sliding away.
    _shownTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) action();
    });
  }

  @override
  void dispose() {
    _shownTimer?.cancel();
    super.dispose();
  }
}

/// A number that counts to its new value when it CHANGES. The first time it
/// appears it just shows the value (no count-from-zero on every screen
/// visit). If the change happens while the screen is covered, the count
/// waits until the screen is back in view.
class CountUp extends StatefulWidget {
  const CountUp({
    super.key,
    required this.value,
    this.style,
    this.suffix = '',
  });

  final int value;
  final TextStyle? style;
  final String suffix;

  @override
  State<CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<CountUp>
    with SingleTickerProviderStateMixin, _WhenShown<CountUp> {
  late final AnimationController _controller;
  late int _from;
  late int _to;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.value;
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(CountUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.value;
    if (target == oldWidget.value) return;
    runWhenShown(() {
      final duration = Fx.dur(const Duration(milliseconds: 700));
      if (duration == Duration.zero) {
        setState(() => _from = _to = target);
        return;
      }
      _from = _shownValue();
      _to = target;
      _controller.duration = duration;
      _controller.forward(from: 0);
    });
  }

  int _shownValue() {
    final t = Curves.easeOutCubic.transform(_controller.value);
    return (_from + (_to - _from) * t).round();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          Text('${_shownValue()}${widget.suffix}', style: widget.style),
    );
  }
}

// ------------------------------------------------------------ change bounce

/// Plays a short effect on its child when [value] changes: a springy pop
/// when it goes UP (a streak grows, a save is added) and a quick shake when
/// it goes DOWN (a streak breaks, a save is used). Full mode only. If the
/// change happens while the screen is covered, it plays once the screen is
/// back in view. Use it on the streak flame and the saves shield.
class ChangeBounce extends StatefulWidget {
  const ChangeBounce({super.key, required this.value, required this.child});

  final int value;
  final Widget child;

  @override
  State<ChangeBounce> createState() => _ChangeBounceState();
}

class _ChangeBounceState extends State<ChangeBounce>
    with SingleTickerProviderStateMixin, _WhenShown<ChangeBounce> {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Fx.celebrate);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 1.4)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.4, end: 1)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 70,
    ),
  ]).animate(_controller);

  bool _gain = true;

  @override
  void didUpdateWidget(ChangeBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value || !Fx.isFull) return;
    final gain = widget.value > oldWidget.value;
    runWhenShown(() {
      _gain = gain;
      _controller.duration = const Duration(milliseconds: 900);
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (_gain) {
          return Transform.scale(scale: _scale.value, child: child);
        }
        final t = _controller.value;
        final dx = sin(t * pi * 7) * (1 - t) * 9;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

// ------------------------------------------------------------------ pop in

/// Scales and fades its child in once, when it first appears. Use it for the
/// crown/check that has just been earned: set [animate] true only for the
/// one that just changed, so the rest stay still.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate || Fx.isOff) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: Fx.dur(Fx.pop),
      curve: Fx.springy,
      child: child,
      builder: (context, v, c) => Transform.scale(
        scale: v,
        child: Opacity(
          opacity: ((v - 0.6) / 0.4).clamp(0.0, 1.0).toDouble(),
          child: c,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ fade + slide

/// Fades and slides its child up slightly, once, when first built. Use for
/// the decree text reveal and for first-load list entry (pass
/// `animate: Fx.firstTime('home_list')`). [index] adds a small stagger in
/// Full mode only (capped, so long lists don't wait).
///
/// [afterRoute]: wait for the page transition this widget sits in to finish
/// before starting. Without it the reveal runs at the same time as the
/// page's own fade and is invisible. If the page is already fully shown
/// (for example the first screen after a notification launch) it starts
/// straight away.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.animate = true,
    this.index = 0,
    this.offset = 12,
    this.duration,
    this.afterRoute = false,
  });

  final Widget child;
  final bool animate;
  final int index;
  final double offset;

  /// Length of the fade. Defaults to [Fx.standard].
  final Duration? duration;
  final bool afterRoute;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _t;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeListener;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || Fx.isOff) return;
    final staggerMs = Fx.isFull ? widget.index.clamp(0, 6) * 40 : 0;
    final total = Fx.dur(widget.duration ?? Fx.standard) +
        Duration(milliseconds: staggerMs);
    if (total.inMilliseconds <= 0) return;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _t = CurvedAnimation(
      parent: controller,
      curve: Interval(
        staggerMs / total.inMilliseconds,
        1,
        curve: Fx.easeOut,
      ),
    );

    final routeAnimation =
        widget.afterRoute ? ModalRoute.of(context)?.animation : null;
    if (routeAnimation != null &&
        routeAnimation.status != AnimationStatus.completed) {
      void listener(AnimationStatus status) {
        if (status != AnimationStatus.completed) return;
        routeAnimation.removeStatusListener(listener);
        _routeListener = null;
        if (mounted) controller.forward();
      }

      _routeAnimation = routeAnimation;
      _routeListener = listener;
      routeAnimation.addStatusListener(listener);
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    final listener = _routeListener;
    if (listener != null) _routeAnimation?.removeStatusListener(listener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: widget.child,
        builder: (context, c) => Transform.translate(
          offset: Offset(0, (1 - t.value) * widget.offset),
          child: c,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- pulse once

/// Pulses its child once (about 1.18x and back) whenever [trigger] changes.
/// Full mode only. Use on the saves shield: trigger = the saves number.
class PulseOnce extends StatefulWidget {
  const PulseOnce({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<PulseOnce> createState() => _PulseOnceState();
}

class _PulseOnceState extends State<PulseOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Fx.standard);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 1.18)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.18, end: 1)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_c);

  @override
  void didUpdateWidget(PulseOnce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && Fx.isFull) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

// ------------------------------------------------------------ hold progress

/// Draws a progress ring around [child] while [progress] runs 0..1. Meant for
/// the hold-to-read button: feed it the hold animation. The ring follows the
/// child's outline (a circle for a square child, a pill for a wide one).
/// It is functional feedback, so it shows at every effects level.
class HoldRing extends StatelessWidget {
  const HoldRing({
    super.key,
    required this.progress,
    required this.child,
    this.color,
    this.strokeWidth = 3,
  });

  final Animation<double> progress;
  final Widget child;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _RingPainter(
        progress,
        color ?? Theme.of(context).colorScheme.primary,
        strokeWidth,
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.strokeWidth)
      : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0).toDouble();
    if (p <= 0) return;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.shortestSide / 2),
      ));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * p), paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

// ----------------------------------------------------------------- confetti

/// A one-shot burst of about 30 small pieces (no package). Inserted into the
/// root overlay by Fx.afterRead; removes itself when done. Full mode only.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.onDone, this.count = 30});

  final VoidCallback onDone;
  final int count;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Piece {
  _Piece({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.phase,
    required this.color,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final double phase;
  final Color color;
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  static const List<Color> _colors = [
    Color(0xFF1FA89A),
    Color(0xFFF28C28),
    Color(0xFFFFC53D),
    Color(0xFF3B82F6),
    Color(0xFF7C5CFF),
  ];

  late final AnimationController _controller;
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    _pieces = List.generate(widget.count, (i) {
      return _Piece(
        angle: -pi / 2 + (rnd.nextDouble() - 0.5) * 2.2,
        speed: 380 + rnd.nextDouble() * 360,
        size: 7 + rnd.nextDouble() * 6,
        spin: (rnd.nextDouble() - 0.5) * 14,
        phase: rnd.nextDouble() * pi,
        color: _colors[rnd.nextInt(_colors.length)],
      );
    });
    _controller = AnimationController(vsync: this, duration: Fx.celebrate)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _ConfettiPainter(_controller, _pieces)),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces) : super(repaint: t);

  final Animation<double> t;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.value;
    final secs = p * 2.0;
    final origin = Offset(size.width / 2, size.height * 0.38);
    final fade = p < 0.7 ? 1.0 : (1 - (p - 0.7) / 0.3).clamp(0.0, 1.0);
    final paint = Paint();
    for (final c in pieces) {
      final dx = cos(c.angle) * c.speed * secs;
      final dy = sin(c.angle) * c.speed * secs + 0.5 * 700 * secs * secs;
      paint.color = c.color.withAlpha((255 * fade).round());
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(c.spin * secs + c.phase);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: c.size,
          height: c.size * 0.55,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}

// --------------------------------------------------------- settings picker

/// The "Effects" choice for the Settings page: Automatic / Full / Reduced /
/// Off, each with an icon, and the selected one highlighted. Drop it into
/// the Settings screen as-is.
class EffectsPicker extends StatelessWidget {
  const EffectsPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<FxLevel?>(
      valueListenable: Fx.choice,
      builder: (context, choice, _) {
        Widget option(
          IconData icon,
          String title,
          String subtitle,
          FxLevel? value,
        ) {
          final selected = choice == value;
          return ListTile(
            selected: selected,
            selectedColor: c.teal,
            selectedTileColor: c.teal.withAlpha(36),
            iconColor: c.muted,
            leading: Icon(icon),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            subtitle: Text(subtitle),
            trailing: selected ? const Icon(Icons.check) : null,
            onTap: () => Fx.setChoice(value),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Effects',
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            option(Icons.phone_android, 'Automatic',
                'Follows your phone\u2019s animation setting', null),
            option(Icons.auto_awesome, 'Full',
                'All animations and celebrations', FxLevel.full),
            option(Icons.tune, 'Reduced',
                'Shorter animations, no celebrations', FxLevel.reduced),
            option(Icons.block, 'Off', 'No animations or vibration',
                FxLevel.off),
          ],
        );
      },
    );
  }
}