import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'toast.dart';

/// Turns reminders on or off for ONE channel decree and shows a message when
/// the device's reminder limit is reached. Shared by the bell button and the
/// decree menu.
Future<void> toggleChannelReminder(BuildContext context, Quote quote) async {
  final state = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final result = await state.setChannelReminder(quote.id, !quote.remindersOn);
  if (result == ReminderToggle.on) {
    final n = quote.reminderMinutes().length;
    showToast(n == 1
        ? 'Reminder set. You will be reminded once daily.'
        : 'Reminder set. You will be reminded $n times daily.');
  } else if (result == ReminderToggle.off) {
    showToast('Reminder off for this decree.');
  }
  if (result == ReminderToggle.limitReached) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Reminder limit reached '
            '(${state.reminderSlotsInUse} a day on this phone). Turn off '
            'another decree\u2019s reminders first.'),
      ),
    );
  }
}

/// Bell that turns reminders on or off for ONE channel decree. Reminders are
/// opt-in per decree so people can stay under their device's alarm limit.
class ReminderBellButton extends StatelessWidget {
  const ReminderBellButton({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final on = quote.remindersOn;

    return IconButton(
      tooltip: on ? 'Reminders on' : 'Remind me',
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        on ? Icons.notifications_active : Icons.notifications_none,
        color: on ? c.teal : c.muted,
      ),
      onPressed: () => toggleChannelReminder(context, quote),
    );
  }
}