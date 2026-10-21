import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../fx.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/fx_widgets.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/toast.dart';

/// Settings: Account (sign in to back up and restore), Effects, and About
/// (installed version and a manual update check). Debug builds also get a
/// Developer section for testing effects; it never appears in release builds.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _version;
  UpdateInfo? _checked;
  bool _checking = false;
  bool _checkFailed = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  Future<void> _signIn(AppState state) async {
    final ok = await showSignInSheet(
      context,
      state,
      title: 'Sign in to back up your decrees.',
    );
    // The sign-in flow restores the account's data itself; this just
    // refreshes the Account row.
    if (ok && mounted) setState(() {});
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _checkFailed = false;
    });
    final info = await UpdateService.check(force: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = info;
      _checkFailed = info == null;
    });
  }

  Widget _header(AppColors c, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _accountTile(AppState state, AppColors c) {
    if (state.isSignedIn) {
      final email = Supabase.instance.client.auth.currentUser?.email;
      return ListTile(
        iconColor: c.teal,
        leading: const Icon(Icons.cloud_done_outlined),
        title: const Text('Signed in'),
        subtitle: Text(
          email == null
              ? 'Your decrees and streaks are backed up.'
              : '$email\nYour decrees and streaks are backed up.',
        ),
        isThreeLine: email != null,
      );
    }
    return ListTile(
      iconColor: c.muted,
      leading: const Icon(Icons.cloud_upload_outlined),
      title: const Text('Sign in to back up and restore'),
      subtitle: const Text(
        'Without an account, your streaks and decrees live only on this phone.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _signIn(state),
    );
  }

  Widget _updateTile(AppColors c) {
    final info = _checked;
    final String subtitle;
    if (_checking) {
      subtitle = 'Checking\u2026';
    } else if (_checkFailed) {
      subtitle = 'Could not check. Try again when you are online.';
    } else if (info == null) {
      subtitle = 'Tap to check';
    } else if (info.available) {
      subtitle = 'Version ${info.latest} is available';
    } else {
      subtitle = 'You are up to date';
    }
    final available = !_checking && info != null && info.available;
    return ListTile(
      iconColor: available ? c.teal : c.muted,
      leading: _checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt),
      title: const Text('Check for updates'),
      subtitle: Text(subtitle),
      trailing: available
          ? TextButton(
              onPressed: () => UpdateService.open(info),
              child: const Text('Update'),
            )
          : null,
      onTap: _checkForUpdates,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _header(c, 'Account'),
          _accountTile(state, c),
          const Divider(),
          const EffectsPicker(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Confetti celebrates ${Fx.milestoneSummary}. Each is '
              'celebrated once, and only in Full mode.',
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
          const Divider(),
          _header(c, 'About'),
          ListTile(
            iconColor: c.muted,
            leading: const Icon(Icons.info_outline),
            title: const Text('iDecree'),
            subtitle: Text(_version == null ? '' : 'Version $_version'),
          ),
          _updateTile(c),
          if (kDebugMode) ...[
            const Divider(),
            _header(c, 'Developer (debug builds only)'),
            ListTile(
              iconColor: c.muted,
              leading: const Icon(Icons.celebration_outlined),
              title: const Text('Play confetti'),
              subtitle: const Text('Needs Effects set to Full'),
              onTap: () => Fx.previewConfetti(context),
            ),
            ListTile(
              iconColor: c.muted,
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset celebrations'),
              subtitle: const Text(
                'Your next decree replays the milestone panel and confetti',
              ),
              onTap: () async {
                await Fx.resetCelebrations();
                showToast('Celebrations reset.');
              },
            ),
            const _EffectsLab(),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Debug only: tries the streak flame and saves shield effects with made-up
/// numbers. It never touches your real streak or saves.
class _EffectsLab extends StatefulWidget {
  const _EffectsLab();

  @override
  State<_EffectsLab> createState() => _EffectsLabState();
}

class _EffectsLabState extends State<_EffectsLab> {
  int _streak = 3;
  int _saves = 2;

  Widget _row({
    required Widget icon,
    required int value,
    required Color color,
    required VoidCallback onLess,
    required VoidCallback onMore,
    required String label,
  }) {
    return Row(
      children: [
        SizedBox(width: 56, child: Center(child: icon)),
        const SizedBox(width: 8),
        CountUp(
          value: value,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
        const Spacer(),
        IconButton(
          tooltip: 'Less (plays the "loss" shake)',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onLess,
        ),
        IconButton(
          tooltip: 'More (plays the "gain" pop)',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onMore,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Effects lab: plus pops, minus shakes (Full mode only)',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _row(
            icon: ChangeBounce(
              value: _streak,
              child: Icon(Icons.local_fire_department,
                  size: 44, color: c.flame),
            ),
            value: _streak,
            color: c.flame,
            label: 'streak',
            onLess: () =>
                setState(() => _streak = _streak > 0 ? _streak - 1 : 0),
            onMore: () => setState(() => _streak++),
          ),
          _row(
            icon: ChangeBounce(
              value: _saves,
              child: Icon(Icons.shield, size: 36, color: c.blue),
            ),
            value: _saves,
            color: c.blue,
            label: 'saves',
            onLess: () => setState(() => _saves = _saves > 0 ? _saves - 1 : 0),
            onMore: () => setState(() => _saves++),
          ),
        ],
      ),
    );
  }
}