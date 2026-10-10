import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'services/circle_service.dart';
import 'services/reminder_service.dart';
import 'services/featured_quote_service.dart';
import 'services/backup_service.dart';
import 'services/channel_service.dart';

enum DueKind { overdue, upcoming, lastRead, none }

class DueInfo {
  DueInfo.overdue(this.minutes)
      : kind = DueKind.overdue,
        lastRead = null;
  DueInfo.upcoming(this.minutes)
      : kind = DueKind.upcoming,
        lastRead = null;
  DueInfo.lastReadAt(this.lastRead)
      : kind = DueKind.lastRead,
        minutes = null;
  DueInfo.none()
      : kind = DueKind.none,
        minutes = null,
        lastRead = null;

  final DueKind kind;
  final int? minutes;
  final DateTime? lastRead;
}

/// A circle as the screens see it: its name and its decrees as [Quote]s.
class Circle {
  Circle({required this.id, required this.name, required this.quotes});

  final String id;
  final String name;
  final List<Quote> quotes;
}

/// All app data lives on the device first (local-first), with Supabase
/// backing for channels, identity, and personal-state backups.
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
  AppState(
    this._prefs,
    this.reminders,
    this.circleService,
    this.featuredQuoteService,
  );

  final SharedPreferences _prefs;
  final ReminderService reminders;
  final CircleService circleService;
  final FeaturedQuoteService featuredQuoteService;

  /// Null until the user signs in; the sign-in sheet attaches it.
  BackupService? backups;

  /// Supabase-backed channel queries. The client is initialized in main()
  /// before AppState.load runs.
  late final _channelServiceForJoined = ChannelService(Supabase.instance.client);

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
  final List<FeaturedQuote> _featuredQuotes = [];

  // quoteId -> (yyyy-MM-dd -> number of reads that day)
  final Map<String, Map<String, int>> _reads = {};
  final Set<String> _frozenDays = {};

  // quoteId -> the moment its most recent read completed. Used only to
  // display "last read" once every read for today is done.
  final Map<String, DateTime> _lastReadAt = {};

  // IDs of Supabase channels the user has joined, persisted so the feed
  // survives restarts. "Circles" from the static JSON remain separate.
  final Set<String> _joinedChannelIds = {};
  static const String _joinedKey = 'joined_channels_v1';

  ThemeMode themeMode = ThemeMode.light;
  int tokens = startingTokens;
  int bestDaily = 0;
  String? _evaluatedThrough; // last past day already checked for a miss
  int _nextNotifBase = 0;

  // ------------------------------------------------------- identity / auth

  bool get isSignedIn => Supabase.instance.client.auth.currentUser != null;

  bool isMemberOf(String channelId) => _joinedChannelIds.contains(channelId);

  // ---------------------------------------------------------------- loading

  static Future<AppState> load(ReminderService reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final circleService = CircleService(url: circleJsonUrl, prefs: prefs);
    final featuredQuoteService =
        FeaturedQuoteService(url: featuredQuotesUrl, prefs: prefs);
    final state = AppState(prefs, reminders, circleService, featuredQuoteService);
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

    // Same idea for the featured-quotes card: show the cached set right
    // away, then refresh it in the background.
    final cachedFeatured = featuredQuoteService.loadCached();
    if (cachedFeatured != null) {
      state._featuredQuotes
        ..clear()
        ..addAll(cachedFeatured);
    }
    unawaited(state.refreshFeaturedQuotes());

    // Joined Supabase channels: load the persisted ID list, then refresh
    // from the server (which also re-syncs memberships when signed in).
    state._loadJoinedIds();
    unawaited(state.refreshJoinedChannels());

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
    final lastRead = j['lastReadAt'] as Map<String, dynamic>? ?? {};
    _lastReadAt.addAll(
        lastRead.map((id, iso) => MapEntry(id, DateTime.parse(iso as String))));
  }

  // ---------------------------------------------------------------- backups

  /// The full state as JSON, for the backup service. Public wrapper over
  /// [_toJson] so the sign-in/restore flow can upload without reaching
  /// into privates.
  Map<String, dynamic> snapshotForBackup() => _toJson();

  /// Merges a backup payload (from user_backups) into current local state.
  /// Rules:
  /// - reads: per quote per day, take the MAX (reads only accumulate).
  /// - quotes: union by id; on id conflict the later edit wins
  ///   (updatedAt; null counts as oldest — covers pre-stamp quotes).
  /// - tokens: backup is authoritative downward (anti-abuse — a stale
  ///   backup can never refill tokens); bestDaily takes the max.
  /// - frozenDays: union.
  /// - evaluatedThrough: take the EARLIER date so missed-day processing
  ///   re-runs over any gap.
  /// Returns true if anything changed (caller saves + notifies).
  bool mergeBackup(Map<String, dynamic> j) {
    var changed = false;

    // Reads: max per quote per day.
    final reads = j['reads'] as Map<String, dynamic>? ?? {};
    reads.forEach((quoteId, days) {
      final incoming = (days as Map<String, dynamic>)
          .map((day, count) => MapEntry(day, count as int));
      final local = _reads.putIfAbsent(quoteId, () => {});
      incoming.forEach((day, count) {
        if ((local[day] ?? 0) < count) {
          local[day] = count;
          changed = true;
        }
      });
    });

    // Quotes: union by id. On id conflict, the later edit wins.
    for (final q in (j['quotes'] as List<dynamic>? ?? [])) {
      final incoming = Quote.fromJson(q as Map<String, dynamic>);
      final local = _quotes.where((l) => l.id == incoming.id).toList();
      if (local.isEmpty) {
        _quotes.add(incoming);
        changed = true;
      } else {
        final l = local.first;
        final localStamp =
            l.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final remoteStamp =
            incoming.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (remoteStamp.isAfter(localStamp)) {
          l.text = incoming.text;
          l.targetPerDay = incoming.targetPerDay;
          l.windowStartMin = incoming.windowStartMin;
          l.windowEndMin = incoming.windowEndMin;
          l.remindersOn = incoming.remindersOn;
          l.updatedAt = incoming.updatedAt;
          changed = true;
        }
      }
    }

    // Tokens: backup is authoritative downward (prevents clear-cache refill).
    final remoteTokens = (j['tokens'] as int?) ?? startingTokens;
    if (remoteTokens < tokens) {
      tokens = remoteTokens;
      changed = true;
    }

    // Best streak: max.
    final remoteBest = (j['bestDaily'] as int?) ?? 0;
    if (remoteBest > bestDaily) {
      bestDaily = remoteBest;
      changed = true;
    }

    // Frozen days: union.
    final remoteFrozen =
        (j['frozenDays'] as List<dynamic>? ?? []).cast<String>();
    final before = _frozenDays.length;
    _frozenDays.addAll(remoteFrozen);
    if (_frozenDays.length != before) changed = true;

    // evaluatedThrough: earlier date wins (re-process any gap).
    final remoteEval = j['evaluatedThrough'] as String?;
    if (remoteEval != null &&
        (_evaluatedThrough == null ||
            remoteEval.compareTo(_evaluatedThrough!) < 0)) {
      _evaluatedThrough = remoteEval;
      changed = true;
    }

    return changed;
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
        'lastReadAt':
            _lastReadAt.map((id, time) => MapEntry(id, time.toIso8601String())),
      };

  Future<void> _save() {
    // Fire-and-forget backup: debounced upload of the same snapshot.
    backups?.scheduleUpload(_toJson());
    return _prefs.setString(_storageKey, jsonEncode(_toJson()));
  }

  // ----------------------------------------------------------------- quotes

  List<Quote> get quotes => List.unmodifiable(_quotes);
  List<Circle> get circles => List.unmodifiable(_circles);

  List<FeaturedQuote> get featuredQuotes =>
      List.unmodifiable(_featuredQuotes);

  Future<void> refreshFeaturedQuotes() async {
    final data = await featuredQuoteService.refresh();
    if (data != null) {
      _featuredQuotes
        ..clear()
        ..addAll(data);
      notifyListeners();
    }
  }

  /// Every decree from every circle, in one list.
  List<Quote> get circleQuotes =>
      List.unmodifiable([for (final c in _circles) ...c.quotes]);

  Circle? circleById(String id) {
    for (final c in _circles) {
      if (c.id == id) {
        return c;
      }
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
    q.updatedAt = clock(); // drives last-edit-wins backup merge
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

  // -------------------------------------------------- joined channels feed

  void _loadJoinedIds() {
    _joinedChannelIds
      ..clear()
      ..addAll(_prefs.getStringList(_joinedKey) ?? const []);
  }

  Future<void> _saveJoinedIds() =>
      _prefs.setStringList(_joinedKey, _joinedChannelIds.toList());

  /// Fetches all joined channels from Supabase and merges them into the
  /// feed alongside any static-JSON circles. When signed in, the SERVER's
  /// membership list is merged in first — so a cleared cache or new
  /// device recovers the feed automatically.
  Future<void> refreshJoinedChannels() async {
    if (isSignedIn) {
      try {
        final serverIds =
            await _channelServiceForJoined.fetchMyMembershipIds();
        final before = _joinedChannelIds.length;
        _joinedChannelIds.addAll(serverIds);
        if (_joinedChannelIds.length != before) await _saveJoinedIds();
      } catch (e) {
        debugPrint('Membership sync failed (using local list): $e');
      }
    }
    if (_joinedChannelIds.isEmpty) return;
    try {
      final data = await _channelServiceForJoined
          .fetchJoined(_joinedChannelIds.toList());
      _applyJoinedChannels(data);
    } catch (e) {
      debugPrint('Joined-channel refresh failed (keeping cache): $e');
    }
  }

  void _applyJoinedChannels(List<JoinedChannelData> data) {
    // Remove previously-joined channels that are no longer joined.
    _circles.removeWhere((c) =>
        _joinedChannelIds.contains(c.id) &&
        !data.any((d) => d.id == c.id));
    for (final ch in data) {
      final quotes = <Quote>[];
      for (final q in ch.quotes) {
        var base = _circleNotifBase[q.id];
        if (base == null) {
          base = _nextNotifBase;
          _nextNotifBase += Quote.maxPerDay + 8;
          _circleNotifBase[q.id] = base;
        }
        quotes.add(Quote(
          id: q.id,
          text: q.text,
          notifBase: base,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          targetPerDay: q.targetPerDay,
          windowStartMin: q.windowStartMin,
          windowEndMin: q.windowEndMin,
          // Agreed: joining does NOT switch on reminders automatically —
          // the user opts in per quote (challenges will rely on this).
          remindersOn: false,
          isCircle: true,
          circleId: ch.id,
        ));
      }
      final existing = _circles.where((c) => c.id == ch.id).toList();
      if (existing.isNotEmpty) {
        existing.first.quotes
          ..clear()
          ..addAll(quotes);
      } else {
        _circles.add(Circle(id: ch.id, name: ch.name, quotes: quotes));
      }
    }
    _save();
    notifyListeners();
    syncReminders();
  }

  // ------------------------------------------------------- join / leave / create

  /// Joins a private channel by its 6-character code. Requires sign-in
  /// (the caller shows the sign-in sheet first; the server enforces it too).
  Future<void> joinChannelByCode(String code) async {
    final joined = await _channelServiceForJoined.joinByCode(code);
    _joinedChannelIds.add(joined.id);
    await _saveJoinedIds();
    await refreshJoinedChannels();
  }

  /// Joins a public channel from the preview screen. Requires sign-in.
  Future<void> joinPublicChannel(String channelId) async {
    await _channelServiceForJoined.join(channelId);
    _joinedChannelIds.add(channelId);
    await _saveJoinedIds();
    await refreshJoinedChannels();
  }

  /// Leaves a channel (owners are refused server-side).
  Future<void> leaveChannel(String channelId) async {
    await _channelServiceForJoined.leave(channelId);
    _joinedChannelIds.remove(channelId);
    await _saveJoinedIds();
    await refreshJoinedChannels();
  }

  /// Called right after create_channel succeeds: the server already made
  /// the creator an owner-member; we track it locally and pull the feed.
  Future<void> joinCreatedChannel(String channelId) async {
    _joinedChannelIds.add(channelId);
    await _saveJoinedIds();
    await refreshJoinedChannels();
  }

  // --------------------------------------------------------- static circles

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
    final now = clock();
    final key = dayKey(now);
    final days = _reads.putIfAbsent(quoteId, () => {});
    days[key] = (days[key] ?? 0) + 1;
    _lastReadAt[quoteId] = now;
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

  DueInfo dueInfoFor(Quote quote) {
    final today = readsTodayFor(quote.id);
    if (!quote.remindersOn) {
      final last = _lastReadAt[quote.id];
      return last != null ? DueInfo.lastReadAt(last) : DueInfo.none();
    }
    final times = quote.reminderMinutes();
    if (today >= times.length) {
      final last = _lastReadAt[quote.id];
      return last != null ? DueInfo.lastReadAt(last) : DueInfo.none();
    }
    final now = clock();
    final nowMin = now.hour * 60 + now.minute;
    final elapsed = times.where((t) => t <= nowMin).length;
    return today < elapsed
        ? DueInfo.overdue(times[today])
        : DueInfo.upcoming(times[today]);
  }

  DueInfo spaceDueInfo(List<Quote> quotes) {
    DueInfo? overdue;
    DueInfo? upcoming;
    DateTime? lastRead;
    for (final q in quotes) {
      final info = dueInfoFor(q);
      switch (info.kind) {
        case DueKind.overdue:
          if (overdue == null || info.minutes! < overdue.minutes!) {
            overdue = info;
          }
          break;
        case DueKind.upcoming:
          if (upcoming == null || info.minutes! < upcoming.minutes!) {
            upcoming = info;
          }
          break;
        case DueKind.lastRead:
          if (lastRead == null || info.lastRead!.isAfter(lastRead)) {
            lastRead = info.lastRead;
          }
          break;
        case DueKind.none:
          break;
      }
    }
    if (overdue != null) return overdue;
    if (upcoming != null) return upcoming;
    if (lastRead != null) return DueInfo.lastReadAt(lastRead);
    return DueInfo.none();
  }

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