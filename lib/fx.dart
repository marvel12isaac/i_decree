// lib/fx.dart
// Central place for every animation/effect decision in iDecree.
//
// Rules this file enforces:
// - One level setting (Full / Reduced / Off) read by every effect.
// - Automatic mode: Full, or Reduced when Android's "remove animations" /
//   animation scale 0 is on. VERIFY on a real phone: this relies on
//   PlatformDispatcher.accessibilityFeatures.disableAnimations.
// - Only scale, opacity and position are animated. No blur, no animated shadows.
// - UI feedback 150-400 ms; the celebration at most ~1.4 s.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart' show AppState;
import 'widgets/fx_widgets.dart' show ConfettiBurst;

enum FxLevel { full, reduced, off }

class Fx {
  Fx._();

  static const String _levelKey = 'fx_level_v1';
  static const String _celebratedKey = 'fx_celebrated_v1';

  static SharedPreferences? _prefs;
  static final Set<String> _celebrated = {};
  static final Set<String> _seenThisSession = {};

  /// The user's choice. null = automatic (follow the phone's setting).
  static final ValueNotifier<FxLevel?> choice = ValueNotifier<FxLevel?>(null);

  // ----------------------------------------------------------- timings

  static const Duration quick = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration pop = Duration(milliseconds: 320);
  static const Duration celebrate = Duration(milliseconds: 1400);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve springy = Curves.easeOutBack;

  // ----------------------------------------------------------- setting

  /// Call once at start-up (main.dart does this).
  static void load(SharedPreferences prefs) {
    _prefs = prefs;
    final raw = prefs.getString(_levelKey);
    choice.value = FxLevel.values.where((l) => l.name == raw).firstOrNull;
    _celebrated
      ..clear()
      ..addAll(prefs.getStringList(_celebratedKey) ?? const <String>[]);
  }

  /// Saves the user's choice. Pass null for "Automatic".
  static Future<void> setChoice(FxLevel? level) async {
    choice.value = level;
    final prefs = _prefs;
    if (prefs == null) return;
    if (level == null) {
      await prefs.remove(_levelKey);
    } else {
      await prefs.setString(_levelKey, level.name);
    }
  }

  /// The level in force right now.
  static FxLevel get level {
    final c = choice.value;
    if (c != null) return c;
    final systemOff = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    return systemOff ? FxLevel.reduced : FxLevel.full;
  }

  static bool get isFull => level == FxLevel.full;
  static bool get isOff => level == FxLevel.off;

  /// Scales a duration for the current level (Reduced is shorter, Off is 0).
  static Duration dur(Duration d) {
    switch (level) {
      case FxLevel.full:
        return d;
      case FxLevel.reduced:
        return d * 0.6;
      case FxLevel.off:
        return Duration.zero;
    }
  }

  // ----------------------------------------------------------- haptics

  /// A light tap. Use only on read completion and milestones, not every tap.
  static void tap() {
    if (!isOff) unawaited(HapticFeedback.lightImpact());
  }

  /// A firmer tap for a completed read.
  static void success() {
    if (!isOff) unawaited(HapticFeedback.mediumImpact());
  }

  // ----------------------------------------------------- once-only helpers

  /// True the first time [id] is asked for in this app session, false after.
  /// Use it so list-entry effects play on first load only, not every rebuild.
  static bool firstTime(String id) => _seenThisSession.add(id);

  // ------------------------------------------------------- milestones

  static const List<int> streakMilestones = [7, 30, 100];

  /// Call right after a read has been registered (after
  /// `AppState.registerRead`). Celebrates a streak of 7, 30 or 100, or the
  /// very first read, once each, ever, on this device.
  static void afterRead(BuildContext context, AppState app) {
    final streak = app.dailyStreak();
    for (final m in streakMilestones) {
      if (streak == m) {
        _celebrateOnce(context, 'streak_$m');
        return;
      }
    }
    if (app.readsTodayAll() >= 1 && app.bestDaily <= 1) {
      _celebrateOnce(context, 'first_read');
    }
  }

  static void _celebrateOnce(BuildContext context, String id) {
    if (!_celebrated.add(id)) return;
    final prefs = _prefs;
    if (prefs != null) {
      unawaited(prefs.setStringList(_celebratedKey, _celebrated.toList()));
    }
    // Marked as done even when effects are reduced, so it never pops up
    // later out of the blue.
    if (isOff) return;
    unawaited(HapticFeedback.heavyImpact());
    if (!isFull) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => ConfettiBurst(
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

/// Page route used for opening decrees: a quick fade plus a small upward
/// slide. No Hero (it can glitch with the hold-position reordering).
class FxPageRoute<T> extends MaterialPageRoute<T> {
  FxPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Fx.dur(Fx.standard);

  @override
  Duration get reverseTransitionDuration => Fx.dur(Fx.quick);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Fx.isOff) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Fx.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}