import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../theme.dart';

/// What signing in gets the user. Shown as a short checklist on the sheet.
const _benefits = [
  'Keep your streaks across devices',
  'Join and follow channels',
  'Create your own channels',
];

/// Wireframe 4: shown when a signed-out user taps Join or Create, or the
/// "Already have an account? Sign in" link on a fresh install.
/// On success, AppState restores the account (personal backup, channel
/// memberships and content) — the "streaks survive reinstall" moment.
/// Returns true if the user is signed in when the sheet closes.
Future<bool> showSignInSheet(
  BuildContext context,
  AppState state, {
  String title = 'Sign in to join.',
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SignInSheet(state: state, title: title),
  );
  return result ?? false;
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({required this.state, required this.title});

  final AppState state;
  final String title;

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

      // --- The backup moment: restore existing data (or start a backup)
      // and bring back channel memberships and content. ---
      await widget.state.restoreAccountData();

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // The full error goes to the log; the user sees a plain message.
      debugPrint('SIGN-IN FLOW ERROR: $e');
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(widget.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Your streaks and decrees will be saved to your account '
              'automatically.',
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            for (final benefit in _benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 18, color: c.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(benefit, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
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
                  : Image.asset(
                      'assets/icons/google_g.png',
                      width: 20,
                      height: 20,
                      // If the asset isn't bundled, fall back to a plain G
                      // instead of a red error box.
                      errorBuilder: (_, __, ___) => const Text('G',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
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
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                child: Text('Not now', style: TextStyle(color: c.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
