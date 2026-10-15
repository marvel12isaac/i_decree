import 'package:flutter/material.dart';

import '../app_state.dart';
import '../legacy_circles.dart';
import 'sign_in_sheet.dart';
import 'toast.dart';

/// One-time prompt for people who used the old hosted-JSON circles: they are
/// now Supabase channels, so offer to join them (signing in if needed). Their
/// read history was already carried over when the app started.
///
/// Call once after Home's first frame. Does nothing when there is no prompt
/// pending. Answering "Not now" or joining ends it for good; a failed join
/// (offline) or a cancelled sign-in leaves it pending for next launch.
Future<void> maybeShowLegacyCirclesPrompt(BuildContext context) async {
  final state = AppScope.of(context);
  if (!state.legacyPromptPending) return;

  final names =
      legacyCircleChannels.values.map((c) => c.name).toList(growable: false);
  final join = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Your circles moved to Channels'),
      content: Text(
        '${names.join(' and ')} are now channels. Join them to keep reading '
        'and keep your progress.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Join'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;

  if (join != true) {
    await state.completeLegacyPrompt();
    return;
  }

  if (!state.isSignedIn) {
    final ok = await showSignInSheet(context, state);
    if (!ok || !context.mounted) return; // still pending: ask again later
  }

  var failed = false;
  for (final channel in legacyCircleChannels.values) {
    if (state.isMemberOf(channel.channelId)) continue;
    try {
      await state.joinPublicChannel(channel.channelId);
    } catch (e) {
      debugPrint('Could not join ${channel.name}: $e');
      failed = true;
    }
  }
  if (!context.mounted) return;

  if (failed) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Could not join everything. We\u2019ll ask again '
              'next time.')),
    );
    return;
  }

  // These readers were already being reminded under the old circles, so turn
  // the bells on for the migrated decrees (up to the device's alarm limit).
  final skipped = await state.enableRemindersForChannels(
    legacyCircleChannels.values.map((c) => c.channelId).toSet(),
  );
  final joined = 'Joined ${names.join(' and ')}.';
  final inUse = state.reminderSlotsInUse;
  showToast(skipped > 0
      ? '$joined Reminders are on, but the limit ($inUse a day) was reached, '
          'so some decrees were left off.'
      : '$joined Reminders are on.');
  await state.completeLegacyPrompt();
}