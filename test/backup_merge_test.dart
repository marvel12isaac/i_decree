import 'package:i_decree/app_state.dart';
import 'package:i_decree/services/circle_service.dart';
import 'package:i_decree/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:i_decree/services/featured_quote_service.dart';

/// Tests for the backup merge rules (AppState.mergeBackup).
/// Run with: flutter test
Future<AppState> _newState(DateTime Function() clock) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final circleService = CircleService(url: 'https://example.com/test.json', prefs: prefs);
  final featuredQuoteService = FeaturedQuoteService(url: featuredQuotesUrl, prefs: prefs);
  final state = AppState(prefs, StubReminderService(), circleService, featuredQuoteService);
  state.clock = clock;
  state.processMissedDays();
  return state;
}

/// A minimal backup payload shaped like AppState._toJson output.
Map<String, dynamic> _payload({
  List<Map<String, dynamic>> quotes = const [],
  Map<String, dynamic> reads = const {},
  List<String> frozenDays = const [],
  int? tokens,
  int? bestDaily,
  String? evaluatedThrough,
}) =>
    {
      'version': 1,
      'quotes': quotes,
      if (reads.isNotEmpty) 'reads': reads,
      if (frozenDays.isNotEmpty) 'frozenDays': frozenDays,
      if (tokens != null) 'tokens': tokens,
      if (bestDaily != null) 'bestDaily': bestDaily,
      if (evaluatedThrough != null) 'evaluatedThrough': evaluatedThrough,
    };

void main() {
  test('merge takes the max reads per quote per day', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    final quote = await state.addQuote(
      text: 'a',
      targetPerDay: 3,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );
    await state.registerRead(quote.id);
    await state.registerRead(quote.id); // local: 2 reads today

    final changed = state.mergeBackup(_payload(reads: {
      quote.id: {'2026-09-01': 5}, // backup claims 5
    }));

    expect(changed, isTrue);
    expect(state.readsTodayFor(quote.id), 5);
  });

  test('merge keeps local reads when they are higher', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    final quote = await state.addQuote(
      text: 'a',
      targetPerDay: 3,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );
    await state.registerRead(quote.id);
    await state.registerRead(quote.id);
    await state.registerRead(quote.id); // local: 3

    final changed = state.mergeBackup(_payload(reads: {
      quote.id: {'2026-09-01': 2}, // backup has fewer
    }));

    expect(changed, isFalse);
    expect(state.readsTodayFor(quote.id), 3);
  });

  test('merge adds remote-only quotes', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);

    final changed = state.mergeBackup(_payload(quotes: [
      {
        'id': 'remote-1',
        'text': 'from another device',
        'notifBase': 0,
        'createdAt': now.toIso8601String(),
        'targetPerDay': 1,
        'windowStartMin': 480,
        'windowEndMin': 1200,
        'remindersOn': false,
      },
    ]));

    expect(changed, isTrue);
    expect(state.quoteById('remote-1'), isNotNull);
  });

  test('merge does not refill tokens (backup authoritative downward)', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    final quote = await state.addQuote(
      text: 'a',
      targetPerDay: 1,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );
    // Burn one token.
    await state.registerRead(quote.id); // Sep 1
    now = DateTime(2026, 9, 3, 9); // Sep 2 missed
    state.processMissedDays();
    expect(state.tokens, AppState.startingTokens - 1);

    // A stale backup claiming the full 2 tokens must not refill them.
    final changed = state.mergeBackup(_payload(tokens: AppState.startingTokens));

    expect(changed, isFalse);
    expect(state.tokens, AppState.startingTokens - 1);
  });

  test('merge takes the max bestDaily', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    expect(state.bestDaily, 0);

    final changed = state.mergeBackup(_payload(bestDaily: 21));

    expect(changed, isTrue);
    expect(state.bestDaily, 21);
  });

  test('merge unions frozen days', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);

    state.mergeBackup(_payload(frozenDays: ['2026-08-30', '2026-08-31']));

    expect(state.isFrozenDay('2026-08-30'), isTrue);
    expect(state.isFrozenDay('2026-08-31'), isTrue);
  });

  test('merge takes the earlier evaluatedThrough to re-process gaps', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    // Local has evaluated through yesterday (2026-08-31).
    expect(state.dailyStreak(), 0);

    // Backup says evaluation only reached Aug 28 — a gap exists.
    final changed =
        state.mergeBackup(_payload(evaluatedThrough: '2026-08-28'));

    expect(changed, isTrue);
    // Internal field isn't public; verify indirectly: processing again
    // after merge doesn't crash and state stays consistent.
    state.processMissedDays();
    expect(state.tokens, AppState.startingTokens);
  });
}