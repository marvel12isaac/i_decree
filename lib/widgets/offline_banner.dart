import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

/// Shown instead of a generic failure message when an action that needs the
/// server (join, create, save) can't get through.
const String offlineActionMessage =
    'You\u2019re offline. Try again when you\u2019re connected.';

/// A slim strip that appears while the server can't be reached and goes away
/// by itself once it can.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isOffline) return const SizedBox.shrink();
    final c = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You\u2019re offline. Showing saved decrees.',
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}