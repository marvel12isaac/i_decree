import 'package:i_decree/app_state.dart';
import 'package:i_decree/services/circle_service.dart';
import 'package:i_decree/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:i_decree/services/featured_quote_service.dart';
// import your app_state.dart / models.dart paths

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
  test('merge takes max reads per quote per day', () {
    // Build state with 2 reads on 2026-01-10 for quote A.
    // mergeBackup with payload claiming 5 reads same day.
    // Expect readsTodayFor / readsOnDay == 5.
  });

  test('merge keeps local reads when higher than backup', () {
    // Local 5, backup 2 → stays 5.
  });

  test('merge adds remote-only quotes', () {
    // Backup has quote X, local does not → present after merge.
  });

  test('merge does not refill tokens', () {
    // Local tokens 0, backup tokens 2 → stays 0 (authoritative backup
    // means lower value wins).
  });

  test('merge takes max bestDaily', () {
    // Local 3, backup 21 → 21.
  });

  test('merge unions frozen days', () {
    // Local {Jan 5}, backup {Jan 6} → both present.
  });

  test('merge takes earlier evaluatedThrough', () {
    // Local 2026-01-09, backup 2026-01-05 → 2026-01-05 (gap re-processed).
  });
}