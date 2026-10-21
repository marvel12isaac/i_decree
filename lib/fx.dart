// lib/fx.dart
// Central place for every animation/effect decision in iDecree.
//
// Rules this file enforces:
// - One level setting (Full / Reduced / Off) read by every effect.
// - Automatic mode: Full, or Reduced when Android's "remove animations" /
//   animation scale 0 is on. VERIFY on a real phone: this relies on
//   PlatformDispatcher.accessibilityFeatures.disableAnimations.
// - Only scale, opacity and position are animated. No blur, no animated shadows.
// - UI feedback roughly 270-650 ms; the celebration about 2 s.

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

  static const Duration quick = Duration(milliseconds: 270);
  static const Duration standard = Duration(milliseconds: 420);
  static const Duration pop = Duration(milliseconds: 480);
  static const Duration celebrate = Duration(milliseconds: 2100);

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

  /// Streak lengths (in days) that get a celebration, up to 3 years. After
  /// that there is one every year (4 years, 5 years, and so on).
  static const List<int> streakMilestones = [
    3, 7, 21, 40, 70, 100, 250, 365, 500, 730, 1000, 1095,
  ];

  static const int _yearDays = 365;

  /// What the Settings page tells people about the celebrations.
  static String get milestoneSummary =>
      'your first decree, streaks of 3, 7, 21, 40, 70, 100, 250, 500 and '
      '1000 days, and every year (1 year, 2 years, 3 years and so on)';

  /// The highest milestone a streak of [streak] days has reached, or null.
  static int? _highestReached(int streak) {
    if (streak >= streakMilestones.last) {
      return (streak ~/ _yearDays) * _yearDays;
    }
    int? best;
    for (final m in streakMilestones) {
      if (streak >= m) best = m;
    }
    return best;
  }

  /// The first milestone above [days].
  static int _nextAfter(int days) {
    for (final m in streakMilestones) {
      if (m > days) return m;
    }
    return (days ~/ _yearDays + 1) * _yearDays;
  }

  static bool _isYear(int days) => days % _yearDays == 0;

  /// "21 days", "1 year", "2 years".
  static String _amount(int days) {
    if (!_isYear(days)) return '$days days';
    final years = days ~/ _yearDays;
    return years == 1 ? '1 year' : '$years years';
  }

  /// "21-day", "1-year", "2-year".
  static String _adjective(int days) =>
      _isYear(days) ? '${days ~/ _yearDays}-year' : '$days-day';

  /// Call right after a read has been registered. Celebrates a streak
  /// milestone, or the very first read, once each, ever, on this device.
  /// Returns the message that goes with the celebration, or null when there
  /// is nothing to celebrate. The caller shows it (in the "Decreed" panel,
  /// or in a toast when effects are off).
  ///
  /// Someone already past a milestone is celebrated for the highest one
  /// they have reached; the lower ones are marked done quietly.
  static String? afterRead(BuildContext context, AppState app) {
    final reached = _highestReached(app.dailyStreak());
    if (reached != null) {
      var changed = false;
      for (final m in streakMilestones) {
        if (m < reached) changed = _celebrated.add('streak_$m') || changed;
      }
      for (var y = streakMilestones.last + _yearDays; y < reached;
          y += _yearDays) {
        changed = _celebrated.add('streak_$y') || changed;
      }
      if (changed) _persistCelebrated();
      if (!_celebrateOnce(context, 'streak_$reached')) return null;
      return '${_adjective(reached)} streak! '
          'Next celebration at ${_amount(_nextAfter(reached))}.';
    }
    if (app.readsTodayAll() >= 1 && app.bestDaily <= 1) {
      if (_celebrateOnce(context, 'first_read')) {
        return 'First decree! '
            'Next celebration at ${_amount(streakMilestones.first)}.';
      }
    }
    return null;
  }

  static void _persistCelebrated() {
    final prefs = _prefs;
    if (prefs != null) {
      unawaited(prefs.setStringList(_celebratedKey, _celebrated.toList()));
    }
  }

  /// Plays the celebration for [id] unless it already happened. True if it
  /// is new (so the caller should show its message).
  static bool _celebrateOnce(BuildContext context, String id) {
    // Marked as done even when effects are reduced or off, so it never pops
    // up later out of the blue.
    if (!_celebrated.add(id)) return false;
    _persistCelebrated();
    if (isOff) return true;
    unawaited(HapticFeedback.heavyImpact());
    if (isFull) _playConfetti(context);
    return true;
  }

  static void _playConfetti(BuildContext context) {
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

  // -------------------------------------------------- debug-only helpers

  /// Forgets which celebrations have played, so they can be tested again.
  static Future<void> resetCelebrations() async {
    _celebrated.clear();
    await _prefs?.remove(_celebratedKey);
  }

  /// Plays the confetti on demand (for testing).
  static void previewConfetti(BuildContext context) {
    if (isOff) return;
    unawaited(HapticFeedback.heavyImpact());
    if (isFull) _playConfetti(context);
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