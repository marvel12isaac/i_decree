import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../theme.dart';

/// Wireframe 4: shown when a signed-out user taps Join or Create.
/// On success, attaches the BackupService to AppState and restores (or
/// uploads) the personal snapshot — the "streaks survive reinstall"
/// moment. Returns true if the user is signed in when the sheet closes.
Future<bool> showSignInSheet(BuildContext context, AppState state) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SignInSheet(state: state),
  );
  return result ?? false;
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({required this.state});

  final AppState state;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AuthService(Supabase.instance.client);
    try {
      final user = await auth.signInWithGoogle();
      if (user == null) {
        // User cancelled the Google sheet.
        if (mounted) setState(() => _busy = false);
        return;
      }

      // --- The backup moment: restore existing data, or start one. ---
      final backups = BackupService(Supabase.instance.client);
      widget.state.backups ??= backups;
      final remote = await backups.fetch();
      if (remote != null) {
        if (widget.state.mergeBackup(remote)) {
          widget.state.processMissedDays();
          await widget.state.syncReminders();
        }
      } else {
        await backups.uploadNow(widget.state.snapshotForBackup());
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Sign-in failed. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Text('Sign in to join.',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Your streaks and decrees will be saved to your account '
              'automatically.',
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(color: c.overdue, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('G',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            Text('One time — takes about 2 taps.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, fontSize: 11)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: Text('Not now', style: TextStyle(color: c.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}