import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

/// Formats [info] as the small status text shown near a decree's read
/// progress: "Due 6:00 PM" if overdue, "Next 8:00 PM" if caught up with more
/// due later, "Last read 7:42 AM" once every read for today is done, or null
/// if there's nothing to show.
String? dueLabelText(BuildContext context, DueInfo info) {
  String fmt(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);
  switch (info.kind) {
    case DueKind.overdue:
      return 'Due ${fmt(info.minutes!)}';
    case DueKind.upcoming:
      return 'Next ${fmt(info.minutes!)}';
    case DueKind.lastRead:
      return 'Last read ${TimeOfDay.fromDateTime(info.lastRead!).format(context)}';
    case DueKind.none:
      return null;
  }
}

/// The color for [info]'s status text: the overdue accent when a read is
/// late, muted for everything else.
Color dueLabelColor(DueInfo info, AppColors c) =>
    info.kind == DueKind.overdue ? c.overdue : c.muted;
