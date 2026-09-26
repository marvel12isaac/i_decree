import 'package:i_decree/app_state.dart';
import 'package:i_decree/services/circle_service.dart';
import 'package:i_decree/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:i_decree/services/featured_quote_service.dart';


/// Tests for the streak and freeze-token rules.
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

void main() {
  test('reading on consecutive days builds the daily streak', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    final quote = await state.addQuote(
      text: 'a',
      targetPerDay: 1,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );

    await state.registerRead(quote.id);
    now = DateTime(2026, 9, 2, 9);
    state.processMissedDays();
    await state.registerRead(quote.id);
    now = DateTime(2026, 9, 3, 9);
    state.processMissedDays();
    await state.registerRead(quote.id);

    expect(state.dailyStreak(), 3);
    expect(state.quoteStreak(quote.id), 3);
    expect(state.tokens, AppState.startingTokens);
  });

  test('a missed day uses a freeze token and keeps the streak', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    final quote = await state.addQuote(
      text: 'a',
      targetPerDay: 1,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );

    await state.registerRead(quote.id); // Sep 1
    now = DateTime(2026, 9, 3, 9); // Sep 2 missed
    state.processMissedDays();
    await state.registerRead(quote.id); // Sep 3

    expect(state.tokens, AppState.startingTokens - 1);
    expect(state.dailyStreak(), 2); // frozen day doesn't add
  });

  test('with no tokens left the streak resets', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    final quote = await state.addQuote(
      text: 'a',
      targetPerDay: 1,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );

    await state.registerRead(quote.id); // Sep 1
    now = DateTime(2026, 9, 5, 9); // Sep 2, 3, 4 missed; only 2 tokens
    state.processMissedDays();
    await state.registerRead(quote.id); // Sep 5

    expect(state.tokens, 0);
    expect(state.dailyStreak(), 1);
    expect(state.bestDaily, 1);
  });

  test('editing a quote keeps its streak, deleting removes it', () async {
    var now = DateTime(2026, 9, 1, 9);
    final state = await _newState(() => now);
    final quote = await state.addQuote(
      text: 'a',
      targetPerDay: 1,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );
    await state.registerRead(quote.id);

    await state.updateQuote(
      quote.id,
      text: 'a, edited',
      targetPerDay: 2,
      windowStartMin: 480,
      windowEndMin: 1200,
      remindersOn: false,
    );
    expect(state.quoteStreak(quote.id), 1);

    await state.deleteQuote(quote.id);
    expect(state.quoteStreak(quote.id), 0);
    expect(state.totalReads(quote.id), 0);
  });
}
