import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// Bell that turns reminders on or off for ONE channel decree. Reminders are
/// opt-in per decree so people can stay under their device's alarm limit.
/// Shows a message when the limit is reached.
class ReminderBellButton extends StatelessWidget {
  const ReminderBellButton({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
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
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final result = await state.setChannelReminder(quote.id, !on);
        if (result == ReminderToggle.limitReached) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                  'Reminder limit reached. Turn off another decree\u2019s '
                  'reminders first.'),
            ),
          );
        }
      },
    );
  }
}
