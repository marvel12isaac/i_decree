import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/circle_service.dart';
import 'services/reminder_service.dart';

/// A circle as the screens see it: its name and its decrees as [Quote]s.
class Circle {
  Circle({required this.id, required this.name, required this.quotes});

  final String id;
  final String name;
  final List<Quote> quotes;
}

/// All app data lives on the device (Stage 1).
///
/// Streak rules (agreed defaults):
/// - Daily streak: a day counts if at least one quote was read that day.
/// - Per-quote streak: a day counts if that quote was read at least once,
///   even if its daily target is higher.
/// - Freeze tokens: each user starts with [startingTokens]. When a day is
///   missed while a streak is active, a token is used automatically and that
///   day becomes a "frozen" day: it neither adds to nor breaks any streak.
/// - No tokens left: the streak resets. The best daily streak is kept.
/// - A "day" is the device's local calendar day.
class AppState extends ChangeNotifier {
  AppState(this._prefs, this.reminders, this.circleService);

  final SharedPreferences _prefs;
  final ReminderService reminders;
  final CircleService circleService;

  /// Overridable clock, so streak logic can be tested.
  DateTime Function() clock = DateTime.now;

  static const String _storageKey = 'app_state_v1';
  static const int startingTokens = 2;
  static const String _themeKey = 'theme_mode_v1';
  
  final List<Quote> _quotes = [];
   final List<Circle> _circles = [];
  // circle quote id -> notifBase, assigned once and kept stable across
  // refreshes/restarts so scheduled notifications don't collide or drift.
  final Map<String, int> _circleNotifBase = {};
  // String? circleName;

  // quoteId -> (yyyy-MM-dd -> number of reads that day)
  final Map<String, Map<String, int>> _reads = {};
  final Set<String> _frozenDays = {};

  ThemeMode themeMode = ThemeMode.light;
  int tokens = startingTokens;  
  int bestDaily = 0;
  String? _evaluatedThrough; // last past day already checked for a miss
  int _nextNotifBase = 0;

  // ---------------------------------------------------------------- loading

  static Future<AppState> load(ReminderService reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final circleService = CircleService(url: circleJsonUrl, prefs: prefs);
    final state = AppState(prefs, reminders, circleService);
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        state._restore(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Could not read saved data: $e');
      }
    }
    state._loadThemeMode();
    state.processMissedDays();

    // Show cached circle content immediately if we have any, then kick off
    // a network refresh in the background without blocking startup.
    final cached = circleService.loadCached();
    if (cached != null) state._applyCircleData(cached, persist: false);
    unawaited(state.refreshCircle());

    return state;
  }

  void _restore(Map<String, dynamic> j) {
    for (final q in (j['quotes'] as List<dynamic>? ?? [])) {
      _quotes.add(Quote.fromJson(q as Map<String, dynamic>));
    }
    final reads = j['reads'] as Map<String, dynamic>? ?? {};
    reads.forEach((quoteId, days) {
      _reads[quoteId] = (days as Map<String, dynamic>)
          .map((day, count) => MapEntry(day, count as int));
    });
    _frozenDays.addAll((j['frozenDays'] as List<dynamic>? ?? []).cast<String>());
    tokens = (j['tokens'] as int?) ?? startingTokens;
    bestDaily = (j['bestDaily'] as int?) ?? 0;
    _evaluatedThrough = j['evaluatedThrough'] as String?;
    _nextNotifBase = (j['nextNotifBase'] as int?) ?? 0;
    final cnb = j['circleNotifBase'] as Map<String, dynamic>? ?? {};
    _circleNotifBase.addAll(cnb.map((k, v) => MapEntry(k, v as int)));
  }

  Map<String, dynamic> _toJson() => {
        'version': 1,
        'quotes': _quotes.map((q) => q.toJson()).toList(),
        'reads': _reads,
        'frozenDays': _frozenDays.toList(),
        'tokens': tokens,
        'bestDaily': bestDaily,
        'evaluatedThrough': _evaluatedThrough,
        'nextNotifBase': _nextNotifBase,
        'circleNotifBase': _circleNotifBase,
      };

  Future<void> _save() =>
      _prefs.setString(_storageKey, jsonEncode(_toJson()));

  // ----------------------------------------------------------------- quotes

  List<Quote> get quotes => List.unmodifiable(_quotes);
  List<Circle> get circles => List.unmodifiable(_circles);

  /// Every decree from every circle, in one list.
  List<Quote> get circleQuotes =>
      List.unmodifiable([for (final c in _circles) ...c.quotes]);

  Circle? circleById(String id) {
    for (final c in _circles) {
      if (c.id == id) return c;
    }
    return null;
  }

  Quote? quoteById(String id) {
    for (final q in _quotes) {
      if (q.id == id) return q;
    }
    for (final q in circleQuotes) {
      if (q.id == id) return q;
    }
    return null;
  }

  Future<Quote> addQuote({
    required String text,
    required int targetPerDay,
    required int windowStartMin,
    required int windowEndMin,
    required bool remindersOn,
  }) async {
    final now = clock();
    final quote = Quote(
      id: now.microsecondsSinceEpoch.toString(),
      text: text,
      notifBase: _nextNotifBase,
      createdAt: now,
      targetPerDay: targetPerDay,
      windowStartMin: windowStartMin,
      windowEndMin: windowEndMin,
      remindersOn: remindersOn,
    );
    _nextNotifBase += Quote.maxPerDay + 8;
    _quotes.insert(0, quote);
    await _save();
    notifyListeners();
    await syncReminders();
    return quote;
  }

  Future<void> updateQuote(
    String id, {
    required String text,
    required int targetPerDay,
    required int windowStartMin,
    required int windowEndMin,
    required bool remindersOn,
  }) async {
    final q = quoteById(id);
    if (q == null || q.isCircle) return;
    q.text = text;
    q.targetPerDay = targetPerDay;
    q.windowStartMin = windowStartMin;
    q.windowEndMin = windowEndMin;
    q.remindersOn = remindersOn;
    await _save();
    notifyListeners();
    await syncReminders();
  }

  /// Deleting a quote also deletes its streak and read history.
  Future<void> deleteQuote(String id) async {
    final q = quoteById(id);
    if (q == null || q.isCircle) return;
    _quotes.removeWhere((q) => q.id == id);
    _reads.remove(id);
    // Notify first: a swiped-away Dismissible must leave the widget tree
    // right away.
    notifyListeners();
    await _save();
    await syncReminders();
  }

  Future<void> syncReminders() =>
      reminders.syncAll([..._quotes, ...circleQuotes]);

  // ---------------------------------------------------------------- circles

  /// Fetches the latest circle content and applies it if the fetch succeeds.
  /// Safe to call repeatedly (e.g. a manual refresh button later).
  Future<void> refreshCircle() async {
    final data = await circleService.refresh();
    if (data != null) _applyCircleData(data, persist: true);
  }

  void _applyCircleData(List<CircleData> data, {required bool persist}) {
    // A decree id must be unique across all circles (reads and reminders
    // are keyed by it), so a repeated id is skipped.
    final seen = <String>{};
    _circles
      ..clear()
      ..addAll(data.map((c) => Circle(
            id: c.id,
            name: c.name,
            quotes: [
              for (final q in c.quotes)
                if (seen.add(q.id)) _circleQuoteFrom(q, c.id),
            ],
          )));
    if (persist) _save();
    notifyListeners();
    syncReminders();
  }

  Quote _circleQuoteFrom(CircleQuoteData d, String circleId) {
    var base = _circleNotifBase[d.id];
    if (base == null) {
      base = _nextNotifBase;
      _nextNotifBase += Quote.maxPerDay + 8;
      _circleNotifBase[d.id] = base;
    }
    return Quote(
      id: d.id,
      text: d.text,
      notifBase: base,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      targetPerDay: d.targetPerDay,
      windowStartMin: d.windowStartMin,
      windowEndMin: d.windowEndMin,
      remindersOn: true,
      isCircle: true,
      circleId: circleId,
    );
  }

  // ------------------------------------------------------------------ reads

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int readsOnDay(String quoteId, String key) => _reads[quoteId]?[key] ?? 0;

  int readsTodayFor(String quoteId) =>
      readsOnDay(quoteId, dayKey(clock()));

  int totalReads(String quoteId) {
    final days = _reads[quoteId];
    if (days == null) return 0;
    return days.values.fold(0, (a, b) => a + b);
  }

  int _readsOnDayAll(String key) {
    var total = 0;
    for (final days in _reads.values) {
      total += days[key] ?? 0;
    }
    return total;
  }

  int readsTodayAll() => _readsOnDayAll(dayKey(clock()));

  /// Call when the user completes a read (after the long-press).
  Future<void> registerRead(String quoteId) async {
    processMissedDays();
    final key = dayKey(clock());
    final days = _reads.putIfAbsent(quoteId, () => {});
    days[key] = (days[key] ?? 0) + 1;
    final streak = dailyStreak();
    if (streak > bestDaily) bestDaily = streak;
    await _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- streaks

  int dailyStreak() => _streak((key) => _readsOnDayAll(key) > 0);

  bool hasReadOnDay(String key) => _readsOnDayAll(key) > 0;

  bool isFrozenDay(String key) => _frozenDays.contains(key);

  /// Reminder slots that have already passed today minus reads done today.
  int unreadCount(Quote quote) {
    final now = clock();
    final minutesNow = now.hour * 60 + now.minute;
    final elapsed =
        quote.reminderMinutes().where((t) => t <= minutesNow).length;
    final remaining = elapsed - readsTodayFor(quote.id);
    return remaining > 0 ? remaining : 0;
  }

  int unreadCountFor(List<Quote> quotes) =>
      quotes.fold(0, (sum, q) => sum + unreadCount(q));

  // ------------------------------------------------------------------ theme

  void _loadThemeMode() {
    switch (_prefs.getString(_themeKey)) {
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      case 'system':
        themeMode = ThemeMode.system;
        break;
      default:
        themeMode = ThemeMode.light;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _prefs.setString(_themeKey, mode.name);
  }
  
  int quoteStreak(String quoteId) =>
      _streak((key) => readsOnDay(quoteId, key) > 0);

  int _streak(bool Function(String key) hasRead) {
    final now = clock();
    var d = DateTime(now.year, now.month, now.day);
    final todayKey = dayKey(d);
    var count = 0;
    for (var i = 0; i < 3650; i++) {
      final key = dayKey(d);
      if (hasRead(key)) {
        count++;
      } else if (_frozenDays.contains(key)) {
        // Frozen day: doesn't add, doesn't break.
      } else if (key == todayKey) {
        // Today isn't over yet, so it can't break the streak.
      } else {
        break;
      }
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return count;
  }

  /// Checks every past day since the last check. If a day was missed while a
  /// streak was active and a token is available, uses a token to freeze it.
  /// Call at startup and whenever the app returns to the foreground.
  void processMissedDays() {
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    if (_evaluatedThrough == null) {
      _evaluatedThrough = dayKey(yesterday);
      _save();
      return;
    }

    var d = DateTime.parse(_evaluatedThrough!);
    d = DateTime(d.year, d.month, d.day + 1);
    var changed = false;

    while (!d.isAfter(yesterday)) {
      final key = dayKey(d);
      final prevKey = dayKey(DateTime(d.year, d.month, d.day - 1));
      final streakWasActive =
          _readsOnDayAll(prevKey) > 0 || _frozenDays.contains(prevKey);
      final missed = _readsOnDayAll(key) == 0 && !_frozenDays.contains(key);
      if (missed && streakWasActive && tokens > 0) {
        tokens--;
        _frozenDays.add(key);
        changed = true;
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }

    final newEvaluated = dayKey(yesterday);
    if (newEvaluated != _evaluatedThrough) {
      _evaluatedThrough = newEvaluated;
      changed = true;
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }
}

/// Makes [AppState] available to every screen.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found above this widget.');
    return scope!.notifier!;
  }
}