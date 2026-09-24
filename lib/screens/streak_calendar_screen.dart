import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

/// How a single calendar day looks in the streak views.
enum DayStatus { read, frozen, missed, future }

/// Works out the status of [day] from existing data only (no new storage).
DayStatus dayStatusFor(AppState state, DateTime day) {
  final now = state.clock();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d.isAfter(today)) return DayStatus.future;
  final key = AppState.dayKey(d);
  if (state.hasReadOnDay(key)) return DayStatus.read;
  if (state.isFrozenDay(key)) return DayStatus.frozen;
  return DayStatus.missed;
}

/// One day marker.
/// - read: filled teal with a check
/// - frozen: blue ring with a snowflake
/// - missed / future: plain ring
/// - today: an extra outer ring
class StreakDayDot extends StatelessWidget {
  const StreakDayDot({
    super.key,
    required this.status,
    this.isToday = false,
    this.size = 28,
  });

  final DayStatus status;
  final bool isToday;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    var fill = Colors.transparent;
    var border = c.ring;
    Widget? icon;

    if (status == DayStatus.read) {
      fill = c.teal;
      border = c.teal;
      icon = Icon(Icons.check, size: size * 0.6, color: c.onTeal);
    } else if (status == DayStatus.frozen) {
      border = c.blue;
      icon = Icon(Icons.ac_unit, size: size * 0.6, color: c.blue);
    } else if (status == DayStatus.future) {
      border = c.line;
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isToday ? c.text : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: border, width: 2),
        ),
        child: icon,
      ),
    );
  }
}

/// Month view of the daily streak, with the same colour coding as the
/// 7-day row on the home screen.
class StreakCalendarScreen extends StatefulWidget {
  const StreakCalendarScreen({super.key});

  @override
  State<StreakCalendarScreen> createState() => _StreakCalendarScreenState();
}

class _StreakCalendarScreenState extends State<StreakCalendarScreen> {
  DateTime? _month; // first day of the month being shown

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);

    final now = state.clock();
    final today = DateTime(now.year, now.month, now.day);
    final currentMonth = DateTime(today.year, today.month);
    _month ??= currentMonth;
    final month = _month!;

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = month.weekday - 1; // week starts on Monday
    final canGoForward = month.isBefore(currentMonth);

    var readDays = 0;
    var frozenDays = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final status = dayStatusFor(state, DateTime(month.year, month.month, d));
      if (status == DayStatus.read) readDays++;
      if (status == DayStatus.frozen) frozenDays++;
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Streak calendar')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() {
                      _month = DateTime(month.year, month.month - 1);
                    }),
                  ),
                  Expanded(
                    child: Text(
                      '${_monthNames[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: canGoForward
                        ? () => setState(() {
                              _month = DateTime(month.year, month.month + 1);
                            })
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final letter in _weekdayLetters)
                    Expanded(
                      child: Center(
                        child: Text(
                          letter,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.75,
                children: [
                  for (var i = 0; i < leadingBlanks; i++)
                    const SizedBox.shrink(),
                  for (var d = 1; d <= daysInMonth; d++)
                    _DayCell(
                      day: d,
                      status: dayStatusFor(
                          state, DateTime(month.year, month.month, d)),
                      isToday: DateTime(month.year, month.month, d) == today,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                frozenDays == 0
                    ? '$readDays ${readDays == 1 ? 'day' : 'days'} read this month'
                    : '$readDays ${readDays == 1 ? 'day' : 'days'} read, '
                        '$frozenDays frozen this month',
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 20),
              Divider(color: c.line),
              const SizedBox(height: 16),
              const Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _LegendItem(status: DayStatus.read, label: 'Read'),
                  _LegendItem(status: DayStatus.frozen, label: 'Freeze used'),
                  _LegendItem(status: DayStatus.missed, label: 'Missed'),
                  _LegendItem(
                    status: DayStatus.missed,
                    label: 'Today',
                    isToday: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.status,
    required this.isToday,
  });

  final int day;
  final DayStatus status;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$day', style: TextStyle(fontSize: 12, color: c.muted)),
        const SizedBox(height: 4),
        StreakDayDot(status: status, isToday: isToday),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.status,
    required this.label,
    this.isToday = false,
  });

  final DayStatus status;
  final String label;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreakDayDot(status: status, isToday: isToday, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
