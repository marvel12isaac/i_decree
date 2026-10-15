import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import '../widgets/share_invite.dart';
import '../widgets/toast.dart';
import 'channel_edit_decrees_screen.dart';
import 'channel_stats_screen.dart';

/// Wireframe 7: channel settings. Owner sees role management, code
/// regeneration, edit decrees, stats, and delete. Admins see members
/// (read-only roles), edit decrees, stats, and leave. Members see the
/// code, and leave.
class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({super.key, required this.channelId});

  final String channelId;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  late final ChannelService _service =
      ChannelService(Supabase.instance.client);

  bool _loading = true;
  String _myRole = 'member';
  ChannelSummary? _summary;
  List<ChannelMemberInfo> _members = [];
  String? _error;

  bool get _isOwner => _myRole == 'owner';
  bool get _isManager => _myRole == 'owner' || _myRole == 'admin';
  bool get _isPrivate => _summary?.joinCode != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.fetchMyRole(widget.channelId),
        _service.fetchSummary(widget.channelId),
        _service.fetchMembers(widget.channelId),
      ]);
      if (!mounted) return;
      setState(() {
        _myRole = results[0] as String;
        _summary = results[1] as ChannelSummary?;
        _members = results[2] as List<ChannelMemberInfo>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load settings.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text('${_summary?.name ?? 'Channel'} · Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: c.muted)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    if (_isManager) ...[
                      _section(context, 'Members (${_members.length})'),
                      for (final m in _members)
                        if (m.role == 'member')
                          _memberRow(context, m),
                      _section(context, 'Admins'),
                      for (final m in _members)
                        if (m.role == 'owner' || m.role == 'admin')
                          _adminRow(context, m),
                    ] else ...[
                      _section(context, 'Members (${_members.length})'),
                      for (final m in _members)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(m.displayName),
                          trailing: m.role == 'owner'
                              ? const Text('owner')
                              : null,
                        ),
                    ],
                    if (_isPrivate) ...[
                      _section(context, 'Join code'),
                      _codeRow(context),
                    ],
                    const SizedBox(height: 8),
                    if (_isManager)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Edit decrees'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChannelEditDecreesScreen(
                                  channelId: widget.channelId),
                            ),
                          );
                          _load(); // counts may have changed
                        },
                      ),
                    if (_isManager)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Participation stats'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChannelStatsScreen(
                                channelId: widget.channelId),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Leave (non-owner) or delete (owner).
                    if (!_isOwner)
                      _dangerRow(context, 'Leave channel', _leave)
                    else
                      _dangerRow(context, 'Delete channel', _delete),
                  ],
                ),
    );
  }

  Widget _section(BuildContext context, String title) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.muted)),
    );
  }

  Widget _memberRow(BuildContext context, ChannelMemberInfo m) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(m.displayName),
      trailing: TextButton(
        onPressed: () => _changeRole(m, 'admin'),
        child: const Text('Make admin'),
      ),
    );
  }

  Widget _adminRow(BuildContext context, ChannelMemberInfo m) {
    // final c = AppColors.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(m.role == 'owner'
          ? '${m.displayName} (owner)'
          : m.displayName),
      trailing: m.role == 'admin'
          ? TextButton(
              onPressed: () => _changeRole(m, 'member'),
              child: Text('Remove',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            )
          : null,
    );
  }

  Widget _codeRow(BuildContext context) {
    final code = _summary?.joinCode ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(code,
          style: const TextStyle(
              fontSize: 20,
              letterSpacing: 4,
              fontWeight: FontWeight.w600)),
      subtitle: const Text('Members join by searching this code'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: () => showShareInviteSheet(
              context,
              channelName: _summary?.name ?? 'this channel',
              joinCode: code.isEmpty ? null : code,
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied')));
            },
          ),
          if (_isManager)
            IconButton(
              tooltip: 'Regenerate',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _regenerate,
            ),
        ],
      ),
    );
  }

  Widget _dangerRow(BuildContext context, String label, VoidCallback onTap) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: error),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        title: Text(label,
            style: TextStyle(color: error, fontWeight: FontWeight.w700)),
        trailing: Icon(Icons.chevron_right, color: error),
        onTap: onTap,
      ),
    );
  }

  Future<void> _changeRole(ChannelMemberInfo m, String role) async {
    try {
      await _service.setRole(widget.channelId, m.userId, role);
      await _load();
      showToast(role == 'admin'
          ? '${m.displayName} is now an admin.'
          : '${m.displayName} is no longer an admin.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change the role.')));
    }
  }

  Future<void> _regenerate() async {
    try {
      await _service.regenerateCode(widget.channelId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New code generated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not regenerate.')));
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this channel?'),
        content: const Text(
            'It leaves your feed. Personal copies you made are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await AppScope.of(context).leaveChannel(widget.channelId);
    if (!mounted) return;
    _popToHome();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this channel?'),
        content: const Text(
            'All its decrees are removed for every member. This cannot be '
            'undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await _service.deleteChannel(widget.channelId);
      if (!mounted) return;
      await AppScope.of(context)
          .leaveChannel(widget.channelId, announce: false);
      if (!mounted) return;
      _popToHome();
      showToast('Channel deleted.');
    } catch (e) {
      if (!mounted) return;
      _showDeleteFailed();
    }
  }

  /// State-context navigation after a mounted check — satisfies
  /// use_build_context_synchronously.
  void _popToHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _showDeleteFailed() {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the channel.')));
  }
}