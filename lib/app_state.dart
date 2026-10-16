import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legacy_circles.dart';
import 'models.dart';
import 'widgets/toast.dart';
import 'services/reminder_service.dart';
import 'services/featured_quote_service.dart';
import 'services/backup_service.dart';
import 'services/channel_service.dart';
import 'services/read_upload_service.dart';

/// [doneToday]: every read for today is done, but the time of the last read
/// isn't known (for example after the phone's data was cleared and today's
/// counts were restored without their times).
enum DueKind { overdue, upcoming, lastRead, doneToday, none }

/// Result of turning a channel decree's reminders on or off.
enum ReminderToggle { on, off, limitReached }

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
  DueInfo.doneToday()
      : kind = DueKind.doneToday,
        minutes = null,
        lastRead = null;
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
    this.featuredQuoteService,
  );

  final SharedPreferences _prefs;
  final ReminderService reminders;
  final FeaturedQuoteService featuredQuoteService;

  /// Null until the user signs in; the sign-in sheet attaches it.
  BackupService? backups;

  /// Supabase-backed channel queries. The client is initialized in main()
  /// before AppState.load runs.
  late final _channelServiceForJoined =
      ChannelService(Supabase.instance.client);
  late final _readUploads = ReadUploadService(Supabase.instance.client);

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

  // Which featured quote is showing. ONE shared index and ONE timer, so the
  // Home card and the My Decrees card always show the same quote.
  final ValueNotifier<int> featuredIndex = ValueNotifier<int>(0);
  final Random _featuredRandom = Random();
  Timer? _featuredTimer;
  static const Duration _featuredRotateEvery = Duration(minutes: 2);

  // Channel decrees the user turned reminders on for. Opt-in per decree and
  // stored on THIS device only: alarm limits are per device.
  static const String _reminderOptInKey = 'channel_reminder_optins_v1';
  final Set<String> _channelReminderOptIns = {};

  // The user's role in each joined channel ('owner' / 'admin' / 'member'),
  // cached with the channel data so buttons that depend on it (add, edit)
  // are right from the first frame instead of flashing in.
  final Map<String, String> _channelRoles = {};

  /// Most reminder alarms this app will schedule at once. Android limits the
  /// alarms an app can hold (commonly cited as about 500), so stay under it.
  static const int maxScheduledReminders = 400;

  // The old hosted-JSON circles moved to Supabase channels. These track the
  // one-time "your circles moved" prompt.
  static const String _legacyDoneKey = 'legacy_circles_prompt_done_v1';
  static const String _legacyCacheKey = 'circle_cache_v1'; // old cache key
  bool legacyPromptPending = false;

  // When channels were last refreshed because the app came to the front.
  DateTime? _lastResumeRefresh;

  // Channel reads waiting for the server to confirm ("quoteId|channelId|day").
  // A read done offline stays here and is uploaded once the phone is back
  // online. Counts are cumulative, so one entry per decree per day is enough.
  final Set<String> _pendingReads = {};
  static const String _pendingReadsKey = 'pending_read_uploads_v1';

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
  // The joined channels' names and decrees, so the feed shows instantly
  // (even offline) while the network refresh runs.
  static const String _joinedCacheKey = 'joined_channel_data_v1';

  ThemeMode themeMode = ThemeMode.light;
  int tokens = startingTokens;
  int bestDaily = 0;
  String? _evaluatedThrough; // last past day already checked for a miss
  int _nextNotifBase = 0;

  // ------------------------------------------------------- identity / auth

  bool get isSignedIn => Supabase.instance.client.auth.currentUser != null;

  bool isMemberOf(String channelId) => _joinedChannelIds.contains(channelId);

  /// The user's cached role in a joined channel, or null if not known yet.
  String? roleFor(String channelId) => _channelRoles[channelId];

  /// Remembers a role a screen just looked up.
  void cacheRole(String channelId, String role) {
    if (!isMemberOf(channelId) || _channelRoles[channelId] == role) return;
    _channelRoles[channelId] = role;
    unawaited(_saveJoinedCache());
  }

  /// True when this device knows of at least one joined channel.
  bool get hasJoinedChannels => _joinedChannelIds.isNotEmpty;

  // ---------------------------------------------------------------- loading

  static Future<AppState> load(ReminderService reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final featuredQuoteService =
        FeaturedQuoteService(url: featuredQuotesUrl, prefs: prefs);
    final state = AppState(prefs, reminders, featuredQuoteService);
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

    // The old hosted-JSON circles now live in Supabase as channels: carry any
    // read history over and work out whether to show the "moved" prompt.
    state._migrateLegacyCircles();

    // Same idea for the featured-quotes card: show the cached set right
    // away, then refresh it in the background.
    final cachedFeatured = featuredQuoteService.loadCached();
    if (cachedFeatured != null) {
      state._featuredQuotes
        ..clear()
        ..addAll(cachedFeatured);
    }
    unawaited(state.refreshFeaturedQuotes());
    state._startFeaturedRotation();

    // Joined Supabase channels: load the persisted ID list and the cached
    // channel content (so the feed shows right away, even offline), then
    // refresh from the server in the background.
    state._loadReminderOptIns();
    state._loadJoinedIds();
    state._loadJoinedCache();
    state._loadPendingReads();
    // Signed in: restore everything tied to the account (personal backup,
    // memberships, channel content) and keep backups uploading. Signed
    // out: just refresh any channels joined on this device.
    unawaited(state.isSignedIn
        ? state.restoreAccountData()
        : state.refreshJoinedChannels());
    // Find out right away whether the server is reachable, and send any
    // channel reads that were still waiting from last time.
    unawaited(state.checkConnection());
    unawaited(state.flushPendingReads());

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

  /// The featured quote at [index] (wraps around), or null if none loaded.
  FeaturedQuote? featuredQuoteAt(int index) => _featuredQuotes.isEmpty
      ? null
      : _featuredQuotes[index % _featuredQuotes.length];

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

  /// Saves the joined channels' names and decrees for instant, offline
  /// startup. Only channels still in the joined list are kept.
  Future<void> _saveJoinedCache() {
    final data = [
      for (final c in _circles)
        if (_joinedChannelIds.contains(c.id))
          {
            'id': c.id,
            'name': c.name,
            'role': _channelRoles[c.id],
            'quotes': [
              for (final q in c.quotes)
                {
                  'id': q.id,
                  'text': q.text,
                  'targetPerDay': q.targetPerDay,
                  'windowStartMin': q.windowStartMin,
                  'windowEndMin': q.windowEndMin,
                },
            ],
          },
    ];
    return _prefs.setString(_joinedCacheKey, jsonEncode(data));
  }

  /// Applies the saved channel content, if any, before the network refresh.
  void _loadJoinedCache() {
    final raw = _prefs.getString(_joinedCacheKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final data = <JoinedChannelData>[];
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as String;
        if (!_joinedChannelIds.contains(id)) continue; // left since caching
        final role = m['role'] as String?;
        if (role != null) _channelRoles[id] = role;
        final rawQuotes = m['quotes'] as List<dynamic>? ?? const [];
        final quotes = <JoinedQuoteData>[];
        for (var i = 0; i < rawQuotes.length; i++) {
          final q = rawQuotes[i] as Map<String, dynamic>;
          quotes.add(JoinedQuoteData(
            id: q['id'] as String,
            text: q['text'] as String,
            targetPerDay: (q['targetPerDay'] as int?) ?? 1,
            windowStartMin: (q['windowStartMin'] as int?) ?? 480,
            windowEndMin: (q['windowEndMin'] as int?) ?? 1200,
            position: i,
          ));
        }
        data.add(JoinedChannelData(
          id: id,
          name: m['name'] as String,
          description: '',
          quotes: quotes,
        ));
      }
      _applyJoinedChannels(data, fromCache: true);
    } catch (e) {
      debugPrint('Could not read cached channels: $e');
    }
  }

  /// Fetches all joined channels from Supabase and merges them into the
  /// feed alongside any static-JSON circles. When signed in, the SERVER's
  /// membership list is merged in first — so a cleared cache or new
  /// device recovers the feed automatically.
  Future<void> refreshJoinedChannels() async {
    if (isSignedIn) {
      try {
        final roles = await _channelServiceForJoined.fetchMyMembershipRoles();
        _channelRoles
          ..clear()
          ..addAll(roles);
        final before = _joinedChannelIds.length;
        _joinedChannelIds.addAll(roles.keys);
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
      reportConnection(online: true);
    } catch (e) {
      debugPrint('Joined-channel refresh failed (keeping cache): $e');
      unawaited(checkConnection());
    }
  }

  void _applyJoinedChannels(
    List<JoinedChannelData> data, {
    bool fromCache = false,
  }) {
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
          // Reminders are per-decree opt-in (alarm limits are per device), so
          // every refresh keeps whatever the user chose.
          remindersOn: _channelReminderOptIns.contains(q.id),
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
    if (!fromCache) {
      // Forget reminder opt-ins for decrees that no longer exist.
      final live = {
        for (final c in _circles)
          for (final q in c.quotes) q.id,
      };
      final before = _channelReminderOptIns.length;
      _channelReminderOptIns.removeWhere((id) => !live.contains(id));
      if (_channelReminderOptIns.length != before) {
        unawaited(_saveReminderOptIns());
      }
      unawaited(_saveJoinedCache());
      _save();
    }
    notifyListeners();
    if (!fromCache) syncReminders();
  }

  // ------------------------------------------------ channel decree reminders

  void _loadReminderOptIns() {
    _channelReminderOptIns
      ..clear()
      ..addAll(_prefs.getStringList(_reminderOptInKey) ?? const []);
  }

  Future<void> _saveReminderOptIns() =>
      _prefs.setStringList(_reminderOptInKey, _channelReminderOptIns.toList());

  /// How many reminder alarms are scheduled right now (personal decrees plus
  /// channel decrees the user opted into).
  int get reminderSlotsInUse {
    var total = 0;
    for (final q in [..._quotes, ...circleQuotes]) {
      if (q.remindersOn) total += q.reminderMinutes().length;
    }
    return total;
  }

  /// Turns reminders on or off for ONE channel decree. Turning on is refused
  /// when it would push the device past [maxScheduledReminders].
  Future<ReminderToggle> setChannelReminder(String quoteId, bool on) async {
    final q = quoteById(quoteId);
    if (q == null || !q.isCircle) return ReminderToggle.off;
    if (on) {
      if (q.remindersOn) return ReminderToggle.on;
      if (reminderSlotsInUse + q.reminderMinutes().length >
          maxScheduledReminders) {
        return ReminderToggle.limitReached;
      }
      await reminders.requestPermission();
      _channelReminderOptIns.add(quoteId);
      q.remindersOn = true;
    } else {
      _channelReminderOptIns.remove(quoteId);
      q.remindersOn = false;
    }
    await _saveReminderOptIns();
    notifyListeners();
    await syncReminders();
    return on ? ReminderToggle.on : ReminderToggle.off;
  }

  // ------------------------------------------------------- bell hint

  static const String bellHint =
      'Tap a decree\u2019s bell to be reminded at its set time.';
  static const String _bellHintKey = 'channel_bell_hint_shown_v1';

  /// Shows [bellHint] the first time a member opens a channel's decree list
  /// (once per channel, on this device). Skipped when a bell is already on.
  Future<void> showBellHintOnce(String channelId) async {
    final shown = _prefs.getStringList(_bellHintKey) ?? const <String>[];
    if (shown.contains(channelId)) return;
    await _prefs.setStringList(_bellHintKey, [...shown, channelId]);
    final circle = circleById(channelId);
    if (circle == null || circle.quotes.any((q) => q.remindersOn)) return;
    showToast(bellHint);
  }

  /// Turns the bell on for every decree in [channelIds], stopping short of
  /// [maxScheduledReminders]. Returns how many decrees were left off because
  /// of the limit. Used for people moving over from the old JSON circles.
  Future<int> enableRemindersForChannels(Set<String> channelIds) async {
    var skipped = 0;
    var changed = false;
    for (final c in _circles) {
      if (!channelIds.contains(c.id)) continue;
      for (final q in c.quotes) {
        if (q.remindersOn) continue;
        if (reminderSlotsInUse + q.reminderMinutes().length >
            maxScheduledReminders) {
          skipped++;
          continue;
        }
        _channelReminderOptIns.add(q.id);
        q.remindersOn = true;
        changed = true;
      }
    }
    if (changed) {
      await reminders.requestPermission();
      await _saveReminderOptIns();
      notifyListeners();
      await syncReminders();
    }
    return skipped;
  }

  // ----------------------------------------------- legacy JSON circles move

  /// One-time move of the old hosted-JSON circles to Supabase channels: any
  /// read history for the old decree ids is carried over to the new ids, and
  /// the "your circles moved" prompt is queued for people who had used them.
  void _migrateLegacyCircles() {
    var moved = false;
    legacyQuoteIdMap.forEach((oldId, newId) {
      final days = _reads.remove(oldId);
      if (days != null) {
        final target = _reads.putIfAbsent(newId, () => <String, int>{});
        days.forEach((day, count) {
          final existing = target[day] ?? 0;
          target[day] = count > existing ? count : existing;
        });
        moved = true;
      }
      final last = _lastReadAt.remove(oldId);
      if (last != null) {
        final current = _lastReadAt[newId];
        if (current == null || last.isAfter(current)) _lastReadAt[newId] = last;
      }
      final base = _circleNotifBase.remove(oldId);
      if (base != null) _circleNotifBase.putIfAbsent(newId, () => base);
    });
    final done = _prefs.getBool(_legacyDoneKey) ?? false;
    legacyPromptPending =
        !done && (moved || _prefs.containsKey(_legacyCacheKey));
    if (moved) _save(); // persist the renamed ids
  }

  /// The prompt was answered (or the user joined): never ask again, and drop
  /// the old circle cache.
  Future<void> completeLegacyPrompt() async {
    legacyPromptPending = false;
    await _prefs.setBool(_legacyDoneKey, true);
    await _prefs.remove(_legacyCacheKey);
  }

  // ------------------------------------------------------ account restore

  /// Restores everything tied to the signed-in account: attaches the backup
  /// service (so uploads keep working), merges the personal backup (decrees,
  /// streaks, saves), then refreshes channel memberships and content. Safe
  /// to call repeatedly. Used at launch and right after sign-in.
  Future<void> restoreAccountData() async {
    if (!isSignedIn) return;
    try {
      backups ??= BackupService(Supabase.instance.client);
      final service = backups!;
      final remote = await service.fetch();
      reportConnection(online: true);
      if (remote != null) {
        if (mergeBackup(remote)) {
          processMissedDays();
          await _save();
          await syncReminders();
        }
      } else {
        // First sign-in on this account: start the backup.
        await service.uploadNow(snapshotForBackup());
      }
    } catch (e) {
      debugPrint('Account restore failed: $e');
      unawaited(checkConnection());
    }
    await refreshJoinedChannels();
    notifyListeners(); // the UI must show what was restored
  }

  /// Called when the app returns to the foreground: re-pull channels and
  /// featured quotes, at most once every few minutes.
  Future<void> refreshOnResume() async {
    if (isOffline) {
      // Don't wait out the throttle: check again as soon as the app is back.
      await _retryConnection();
      return;
    }
    final now = clock();
    final last = _lastResumeRefresh;
    if (last != null && now.difference(last) < const Duration(minutes: 5)) {
      return;
    }
    _lastResumeRefresh = now;
    await refreshJoinedChannels();
    unawaited(refreshFeaturedQuotes());
    unawaited(flushPendingReads());
  }

  // ---------------------------------------------------------- connectivity

  /// True when the last check found the server unreachable. The app keeps
  /// working from its saved copy; screens show an offline banner. It is based
  /// on real requests (not just "Wi-Fi is on"), so it also catches a
  /// connection with no internet.
  bool isOffline = false;
  Timer? _offlineRetryTimer;

  /// Records the result of reaching (or failing to reach) the server.
  void reportConnection({required bool online}) {
    if (isOffline == !online) return;
    isOffline = !online;
    if (isOffline) {
      _offlineRetryTimer?.cancel();
      _offlineRetryTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => unawaited(_retryConnection()),
      );
    } else {
      _offlineRetryTimer?.cancel();
      _offlineRetryTimer = null;
      unawaited(flushPendingReads());
    }
    notifyListeners();
  }

  /// A tiny request that tells us whether the server can be reached. Any
  /// failed request calls this, so a server-side error is not mistaken for
  /// being offline.
  Future<bool> checkConnection() async {
    try {
      await Supabase.instance.client
          .from('channels')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 8));
      reportConnection(online: true);
      return true;
    } catch (e) {
      debugPrint('Connection check failed: $e');
      reportConnection(online: false);
      return false;
    }
  }

  Future<void> _retryConnection() async {
    if (await checkConnection()) {
      unawaited(refreshJoinedChannels());
      unawaited(refreshFeaturedQuotes());
    }
  }

  // ---------------------------------------------------- featured rotation

  void _startFeaturedRotation() {
    _featuredTimer?.cancel();
    _featuredTimer =
        Timer.periodic(_featuredRotateEvery, (_) => _rotateFeatured());
  }

  void _rotateFeatured() {
    final n = _featuredQuotes.length;
    if (n < 2) return;
    var next = _featuredRandom.nextInt(n);
    if (next == featuredIndex.value % n) next = (next + 1) % n;
    featuredIndex.value = next;
  }

  @override
  void dispose() {
    _featuredTimer?.cancel();
    _offlineRetryTimer?.cancel();
    featuredIndex.dispose();
    super.dispose();
  }

  // -------------------------------------------------- join / leave / create

  /// Joins a private channel by its 6-character code. Requires sign-in
  /// (the caller shows the sign-in sheet first; the server enforces it too).
  Future<void> joinChannelByCode(String code) async {
    final joined = await _channelServiceForJoined.joinByCode(code);
    _joinedChannelIds.add(joined.id);
    await _saveJoinedIds();
    await refreshJoinedChannels();
    showToast('Joined ${joined.name}. $bellHint');
  }

  /// Joins a public channel from the channel list screen. Requires sign-in.
  Future<void> joinPublicChannel(String channelId) async {
    await _channelServiceForJoined.join(channelId);
    _joinedChannelIds.add(channelId);
    await _saveJoinedIds();
    await refreshJoinedChannels();
    showToast(
        'Joined ${circleById(channelId)?.name ?? 'the channel'}. $bellHint');
  }

  /// Leaves a channel (owners are refused server-side).
  Future<void> leaveChannel(String channelId, {bool announce = true}) async {
    final leftName = circleById(channelId)?.name;
    await _channelServiceForJoined.leave(channelId);
    _joinedChannelIds.remove(channelId);
    _channelRoles.remove(channelId);
    // Its decrees' reminder opt-ins go with it.
    final left = circleById(channelId);
    if (left != null) {
      _channelReminderOptIns.removeAll(left.quotes.map((q) => q.id));
      await _saveReminderOptIns();
    }
    // Drop it from the feed now. Refreshing only re-applies channels that
    // are still joined, so a left channel would otherwise linger.
    _circles.removeWhere((c) => c.id == channelId);
    await _saveJoinedIds();
    await _saveJoinedCache();
    notifyListeners();
    await syncReminders();
    await refreshJoinedChannels();
    if (announce) showToast('You left ${leftName ?? 'the channel'}.');
  }

  /// Called right after create_channel succeeds: the server already made
  /// the creator an owner-member; we track it locally and pull the feed.
  Future<void> joinCreatedChannel(String channelId) async {
    _joinedChannelIds.add(channelId);
    await _saveJoinedIds();
    await refreshJoinedChannels();
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
  ///
  /// Channel-decree reads by MEMBERS are uploaded to read_events
  /// (fire-and-forget, cumulative count) — this is what creator stats are
  /// built from. Personal reads and non-member reads stay local-only.
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
    _maybeUploadRead(quoteId, key);
  }

  /// Fire-and-forget upload of a channel-decree read by a member.
  void _maybeUploadRead(String quoteId, String dayK) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return; // not signed in: local-only
    Quote? q;
    for (final quote in _quotes) {
      if (quote.id == quoteId) return; // personal decree: never uploads
    }
    for (final c in _circles) {
      for (final quote in c.quotes) {
        if (quote.id == quoteId) {
          q = quote;
          break;
        }
      }
      if (q != null) break;
    }
    if (q == null || !q.isCircle) return;
    final channelId = q.circleId;
    if (channelId == null || !_joinedChannelIds.contains(channelId)) {
      return; // browsing without membership: local-only (agreed rule)
    }
    // Remember the read until the server confirms it, so a read done offline
    // is sent later.
    final key = '$quoteId|$channelId|$dayK';
    _pendingReads.add(key);
    unawaited(_savePendingReads());
    unawaited(_uploadPendingRead(key));
  }

  void _loadPendingReads() {
    _pendingReads
      ..clear()
      ..addAll(_prefs.getStringList(_pendingReadsKey) ?? const []);
  }

  Future<void> _savePendingReads() =>
      _prefs.setStringList(_pendingReadsKey, _pendingReads.toList());

  Future<void> _uploadPendingRead(String key) async {
    final parts = key.split('|');
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return; // signed out: keep it for when they sign in
       if (parts.length != 3) {
      _pendingReads.remove(key); // malformed entry
      unawaited(_savePendingReads());
      return;
    }
    final count = _reads[parts[0]]?[parts[2]];
    if (count == null) {
      _pendingReads.remove(key); // the read history is gone
      unawaited(_savePendingReads());
      return;
    }
    final ok = await _readUploads.uploadRead(
      quoteId: parts[0],
      channelId: parts[1],
      userId: user.id,
      dayKey: parts[2],
      countForToday: count,
    );
    if (ok) {
      _pendingReads.remove(key);
      unawaited(_savePendingReads());
      reportConnection(online: true);
    } else {
      unawaited(checkConnection());
    }
  }

  /// Sends every channel read that is still waiting. Entries older than two
  /// weeks are dropped so a read the server keeps refusing can't pile up.
  Future<void> flushPendingReads() async {
    if (_pendingReads.isEmpty) return;
    final cutoff = dayKey(clock().subtract(const Duration(days: 14)));
    _pendingReads.removeWhere((k) => k.split('|').last.compareTo(cutoff) < 0);
    for (final key in _pendingReads.toList()) {
      await _uploadPendingRead(key);
    }
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

  /// The number on a channel's pill: reads that are due now but not done,
  /// counting only decrees that have reminders on. It goes up as more reads
  /// fall due and down as they are read. (5 decrees at 2 reads each is at
  /// most 10, once every read is due.)
  int unreadCountFor(List<Quote> quotes) => quotes
      .where((q) => q.remindersOn)
      .fold(0, (sum, q) => sum + unreadCount(q));

  // Home's channel order for this session (see channelsByDue).
  List<String>? _homeOrder;
  Map<String, DueKind> _homeKinds = {};
  String? _homeOrderDay;

  /// Joined channels in Home order. Channels with a read due now come first:
  /// the most recently due on top, the longest-waiting at the bottom of that
  /// group. Then channels with a next due time, soonest first. Then channels
  /// decreed most recently, then the rest.
  ///
  /// That is the order on a cold start (and on the first call each new day).
  /// After that the order HOLDS: reading a decree updates the channel's pill
  /// and status in place but never moves it, so people can see what they have
  /// done without hunting for the channel. Only a channel that newly becomes
  /// due (or a newly joined one) rises to the top. The order lives in memory,
  /// so killing the app resets it.
  List<Circle> channelsByDue() {
    final infos = {for (final c in _circles) c.id: spaceDueInfo(c.quotes)};
    int rank(DueKind kind) {
      switch (kind) {
        case DueKind.overdue:
          return 0;
        case DueKind.upcoming:
          return 1;
        case DueKind.lastRead:
          return 2;
        case DueKind.doneToday:
          return 3;
        case DueKind.none:
          return 4;
      }
    }

    final sorted = [..._circles];
    sorted.sort((a, b) {
      final da = infos[a.id]!;
      final db = infos[b.id]!;
      final byRank = rank(da.kind).compareTo(rank(db.kind));
      if (byRank != 0) return byRank;
      var cmp = 0;
      if (da.kind == DueKind.overdue) {
        cmp = db.minutes!.compareTo(da.minutes!); // most recently due first
      } else if (da.kind == DueKind.upcoming) {
        cmp = da.minutes!.compareTo(db.minutes!); // soonest next due first
      } else if (da.kind == DueKind.lastRead) {
        cmp = db.lastRead!.compareTo(da.lastRead!); // decreed most recently
      }
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final today = dayKey(clock());
    final previous = _homeOrder;
    if (previous == null || _homeOrderDay != today) {
      _homeOrder = [for (final c in sorted) c.id];
      _homeKinds = {for (final c in sorted) c.id: infos[c.id]!.kind};
      _homeOrderDay = today;
      return sorted;
    }

    final byId = {for (final c in _circles) c.id: c};
    final defaultIndex = {
      for (var i = 0; i < sorted.length; i++) sorted[i].id: i,
    };
    final risen = <String>[]; // newly due, or newly joined: go to the top
    final kept = <String>[]; // everyone else keeps their place
    for (final id in previous) {
      if (!byId.containsKey(id)) continue; // left or deleted
      final nowDue = infos[id]!.kind == DueKind.overdue;
      final wasDue = _homeKinds[id] == DueKind.overdue;
      if (nowDue && !wasDue) {
        risen.add(id);
      } else {
        kept.add(id);
      }
    }
    final known = previous.toSet();
    for (final c in sorted) {
      if (!known.contains(c.id)) risen.add(c.id);
    }
    risen.sort((a, b) => defaultIndex[a]!.compareTo(defaultIndex[b]!));

    final next = [...risen, ...kept];
    _homeOrder = next;
    _homeKinds = {for (final c in sorted) c.id: infos[c.id]!.kind};
    return [for (final id in next) byId[id]!];
  }

  DueInfo dueInfoFor(Quote quote) {
    // Status comes from the schedule for EVERY decree, whether or not its
    // bell is on (the bell only controls notifications). It is never blank:
    // a decree always has a due time, a next time, or, once every read for
    // today is done, a "last decreed" time (so a stale one from an earlier
    // day can't show).
    final today = readsTodayFor(quote.id);
    final times = quote.reminderMinutes();
    // "Done for today" follows the read target (the crowns). A window whose
    // end is not after its start has only one time slot, so the remaining
    // reads share that last slot instead of counting as done.
    final target = quote.targetPerDay.clamp(1, Quote.maxPerDay).toInt();
    final now = clock();
    if (today >= target) {
      // Show the real time of the last read, but only if it was TODAY. If the
      // time is missing (or is from an earlier day), say "Done today" rather
      // than invent one. The next read saves a fresh time and replaces this.
      final last = _lastReadAt[quote.id];
      if (last != null && dayKey(last) == dayKey(now)) {
        return DueInfo.lastReadAt(last);
      }
      return DueInfo.doneToday();
    }
    final nowMin = now.hour * 60 + now.minute;
    final elapsed = times.where((t) => t <= nowMin).length;
    final slot = times[today < times.length ? today : times.length - 1];
    final isDue = today < times.length ? today < elapsed : slot <= nowMin;
    return isDue ? DueInfo.overdue(slot) : DueInfo.upcoming(slot);
  }

  DueInfo spaceDueInfo(List<Quote> quotes) {
    DueInfo? overdue;
    DueInfo? upcoming;
    DateTime? lastRead;
    var anyDoneToday = false;
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
        case DueKind.doneToday:
          anyDoneToday = true;
          break;
        case DueKind.none:
          break;
      }
    }
    if (overdue != null) return overdue;
    if (upcoming != null) return upcoming;
    if (lastRead != null) return DueInfo.lastReadAt(lastRead);
    if (anyDoneToday) return DueInfo.doneToday();
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