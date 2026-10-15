import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_links.dart';
import 'toast.dart';

/// The text people send to invite someone to a channel. Private channels
/// share the join code; public ones share the name (people find them by name
/// in search).
String channelInviteMessage({required String channelName, String? joinCode}) {
  if (joinCode != null) {
    return 'Join my "$channelName" channel on iDecree!\n'
        'Get the app: $appDownloadUrl\n'
        'Then open it and search this code: $joinCode';
  }
  return 'Join the "$channelName" channel on iDecree!\n'
      'Get the app: $appDownloadUrl\n'
      'Then open it and search for "$channelName".';
}

/// Opens the share options: the phone's own share sheet (WhatsApp, Telegram,
/// SMS and any other app that can take text), or a plain copy.
Future<void> showShareInviteSheet(
  BuildContext context, {
  required String channelName,
  String? joinCode,
}) {
  final message =
      channelInviteMessage(channelName: channelName, joinCode: joinCode);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share with\u2026'),
            subtitle: const Text('WhatsApp, Telegram, SMS and more'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _shareText(message, channelName);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy invite message'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _copy(message, 'Invite message copied');
            },
          ),
          if (joinCode != null)
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Copy code only'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _copy(joinCode, 'Code copied');
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _copy(String text, String toast) async {
  await Clipboard.setData(ClipboardData(text: text));
  showToast(toast);
}

Future<void> _shareText(String message, String channelName) async {
  try {
    // VERIFY: share_plus API for the version in pubspec.yaml (11.0.0 and
    // later use SharePlus.instance.share(ShareParams(...))).
    await SharePlus.instance.share(
      ShareParams(text: message, subject: 'Join $channelName on iDecree'),
    );
  } catch (e) {
    debugPrint('Share failed: $e');
    await _copy(message, 'Could not open sharing. Invite message copied.');
  }
}