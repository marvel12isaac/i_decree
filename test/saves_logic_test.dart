import 'package:flutter_test/flutter_test.dart';

import 'package:i_decree/app_state.dart';

// Tests the streak-save rules that do not need a phone: the caps and which
// milestones pay out. Run with:  flutter test test/saves_logic_test.dart
void main() {
  group('saveCapFor', () {
    test('3 under 40 days, 4 from 40, 5 from 1 year', () {
      expect(AppState.saveCapFor(0), 3);
      expect(AppState.saveCapFor(39), 3);
      expect(AppState.saveCapFor(40), 4);
      expect(AppState.saveCapFor(364), 4);
      expect(AppState.saveCapFor(365), 5);
      expect(AppState.saveCapFor(2000), 5);
    });
  });

  group('awardsBetween', () {
    test('nothing before day 7', () {
      expect(AppState.awardsBetween(0, 6), isEmpty);
    });

    test('pays each milestone once', () {
      expect(AppState.awardsBetween(0, 7), [7]);
      expect(AppState.awardsBetween(7, 7), isEmpty);
      expect(AppState.awardsBetween(7, 40), [40]);
      expect(AppState.awardsBetween(40, 99), isEmpty);
    });

    test('catches up several at once, in order', () {
      expect(AppState.awardsBetween(0, 45), [7, 40]);
      expect(AppState.awardsBetween(0, 365), [7, 40, 100, 250, 365]);
    });

    test('years: 1, 2, 3, then every year', () {
      expect(AppState.awardsBetween(365, 730), [730]);
      expect(AppState.awardsBetween(730, 1095), [1095]);
      expect(AppState.awardsBetween(1095, 1459), isEmpty);
      expect(AppState.awardsBetween(1095, 1460), [1460]);
      expect(AppState.awardsBetween(1460, 1825), [1825]);
    });

    test('no saves at the celebration-only milestones', () {
      final all = AppState.awardsBetween(0, 1100);
      for (final celebrationOnly in [3, 21, 70, 500, 1000]) {
        expect(all.contains(celebrationOnly), isFalse);
      }
    });
  });

  group('highestAwardAtOrBelow', () {
    test('finds the latest milestone already behind a streak', () {
      expect(AppState.highestAwardAtOrBelow(6), 0);
      expect(AppState.highestAwardAtOrBelow(7), 7);
      expect(AppState.highestAwardAtOrBelow(99), 40);
      expect(AppState.highestAwardAtOrBelow(300), 250);
      expect(AppState.highestAwardAtOrBelow(1500), 1460);
    });
  });
}