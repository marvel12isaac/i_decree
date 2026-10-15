import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import '../widgets/offline_banner.dart';
import '../widgets/share_invite.dart';
import '../widgets/due_time.dart';
import '../widgets/quote_text.dart';
import '../widgets/read_crowns.dart';
import '../widgets/reminder_bell.dart';
import '../widgets/report_dialog.dart';
import '../widgets/sign_in_sheet.dart';
import 'channel_settings_screen.dart';
import 'quote_editor_screen.dart';
import 'quote_view_screen.dart';

/// One channel's decree list — the single channel screen.
///
/// Member mode: bold title/body rows, due status, crowns, tap to read,
/// and an overflow menu (settings for managers, share code, report,
/// leave). Preview mode (from search, not a member): the SAME layout plus
/// a join banner; rows open the quote view, which gates decreeing/adding
/// behind joining. Header shows member and decree counts in both modes.
class CircleQuoteListScreen extends StatefulWidget {
  const CircleQuoteListScreen({
    super.key,
    required this.circleId,
    this.channelName,
    this.memberCount,
    this.decreesCount,
    this.joinCode,
    this.preloadedQuotes,
    this.isChannelPreview = false,
  });

  final String circleId;
  final String? channelName;
  final int? memberCount;
  final int? decreesCount;
  final String? joinCode;
  final List<ChannelDecreePreview>? preloadedQuotes;
  final bool isChannelPreview;

  @override
  State<CircleQuoteListScreen> createState() => _CircleQuoteListScreenState();
}

class _CircleQuoteListScreenState extends State<CircleQuoteListScreen> {
  Timer? _clockTimer;

  List<ChannelDecreePreview>? _previewDecrees;
  bool _loadingPreview = false;
  bool _previewRequested = false;
  String? _error;
  bool _joining = false;

  bool _countsTried = false;
  int? _fetchedMemberCount;
  int? _fetchedDecreesCount;

  // Role, for the overflow menu. 'member' for static circles.
  String _myRole = 'member';
  bool _roleKnown = false; // true once the role is cached or looked up
  String? _knownCode;

  static final _uuidRe =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}', caseSensitive: false);
  bool get _isSupabaseChannel => _uuidRe.hasMatch(widget.circleId);

  bool get _isManager => _myRole == 'owner' || _myRole == 'admin';

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadRoleAndCode();
    // First time a member opens this channel's list: point at the bell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.of(context);
      if (!state.isMemberOf(widget.circleId)) return;
      state.showBellHintOnce(widget.circleId);
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRoleAndCode() async {
    if (!_isSupabaseChannel) return;
    final service = ChannelService(Supabase.instance.client);
    try {
      final role = await service.fetchMyRole(widget.circleId);
      if (!mounted) return;
      setState(() {
        _myRole = role;
        _roleKnown = true;
      });
      AppScope.of(context).cacheRole(widget.circleId, role);
    } catch (_) {}
    try {
      final s = await service.fetchSummary(widget.circleId);
      if (!mounted || s == null) return;
      setState(() => _knownCode = s.joinCode);
    } catch (_) {}
  }

  /// Managers add a decree to the channel from this list.
  Future<void> _addDecree() async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final count = state.circleById(widget.circleId)?.quotes.length ?? 0;
    if (count >= 33) {
      messenger.showSnackBar(const SnackBar(
          content: Text('A channel can have up to 33 decrees.')));
      return;
    }
    final draft = await Navigator.of(context).push<DecreeDraft>(
      MaterialPageRoute(builder: (_) => const QuoteEditorScreen.draft()),
    );
    if (draft == null || !mounted) return;
    try {
      await ChannelService(Supabase.instance.client).addDecree(
        widget.circleId,
        text: draft.text,
        targetPerDay: draft.targetPerDay,
        windowStartMin: draft.windowStartMin,
        windowEndMin: draft.windowEndMin,
        position: count,
      );
      await state.refreshJoinedChannels();
      messenger.showSnackBar(const SnackBar(content: Text('Decree added.')));
      _fetchCounts(); // the header's decree count changed
    } catch (e) {
      debugPrint('Could not add decree: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add the decree. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);

    final circle = state.circleById(widget.circleId);
    final inFeed = circle != null;
    final preview =
        widget.isChannelPreview && !state.isMemberOf(widget.circleId);

    // A cached role means the add button is right from the first frame.
    if (!_roleKnown) {
      final cached = state.roleFor(widget.circleId);
      if (cached != null) {
        _myRole = cached;
        _roleKnown = true;
      }
    }
    final canAdd = !preview && _roleKnown && _isManager && _isSupabaseChannel;

    // Only people who have NOT joined need the server's copy of the decrees.
    // Members always read from the saved copy, so being offline never blanks
    // their list.
    _requestPreviewIfNeeded(preview);

    final title = circle?.name ?? widget.channelName ?? 'Channel';
    final memberCount = widget.memberCount ?? _fetchedMemberCount;
    final decreesCount = widget.decreesCount ?? _fetchedDecreesCount;
    final countsLine = (memberCount != null || decreesCount != null)
        ? '${_plural(memberCount ?? 0, 'member', 'members')} · '
            '${_plural(decreesCount ?? 0, 'decree', 'decrees')}'
        : null;

    if (countsLine == null && inFeed && !_countsTried) {
      _countsTried = true;
      _fetchCounts();
    }

    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: canAdd
          ? FloatingActionButton(
              tooltip: 'Add a decree',
              onPressed: _addDecree,
              child: const Icon(Icons.add),
            )
          : null,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17)),
            if (countsLine != null)
              Text(countsLine, style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
        actions: [
          if (canAdd)
            IconButton(
              tooltip: 'Add a decree',
              icon: const Icon(Icons.add),
              onPressed: _addDecree,
            ),
          // Non-members get no menu: they can't report or manage anything.
          if (!preview) _buildMenu(context, state),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          if (preview) _buildJoinBanner(context, state, c),
          Expanded(
              child: _buildBody(context, state, c, preview, inFeed, circle)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- menu

  Widget _buildMenu(BuildContext context, AppState state) {
    return PopupMenuButton<String>(
      onSelected: (value) => _onMenu(value, state),
      itemBuilder: (context) => [
        if (_isManager && _isSupabaseChannel)
          const PopupMenuItem(value: 'settings', child: Text('Channel settings')),
        if (_isManager && _isSupabaseChannel)
          const PopupMenuItem(
              value: 'stats', child: Text('Participation stats')),
        if (_knownCode != null)
          const PopupMenuItem(value: 'share', child: Text('Share code')),
        if (_isSupabaseChannel && _myRole != 'owner')
          const PopupMenuItem(value: 'report', child: Text('Report channel')),
        if (_isSupabaseChannel && _myRole != 'owner')
          const PopupMenuItem(
              value: 'leave',
              child: Text('Leave channel',
                  style: TextStyle(color: Colors.red))),
      ],
    );
  }

  Future<void> _onMenu(String value, AppState state) async {
    switch (value) {
      case 'settings':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ChannelSettingsScreen(channelId: widget.circleId),
          ),
        );
        await state.refreshJoinedChannels(); // edits/deletes may have landed
        break;
      case 'stats':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChannelSettingsScreen(channelId: widget.circleId),
          ),
        );
        break;
      case 'share':
        final code = _knownCode;
        if (code == null) break;
        await showShareInviteSheet(
          context,
          channelName: widget.channelName ??
              state.circleById(widget.circleId)?.name ??
              'this channel',
          joinCode: code,
        );
        break;
      case 'report':
        await showReportDialog(
          context,
          state,
          ReportTarget.channel(channelId: widget.circleId),
        );
        break;
      case 'leave':
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
        if (confirmed == true) {
          await state.leaveChannel(widget.circleId);
          if (mounted) Navigator.of(context).pop();
        }
        break;
    }
  }

  // ------------------------------------------------------------- preview

  void _requestPreviewIfNeeded(bool preview) {
    if (!preview || _previewRequested) return;
    _previewRequested = true;
    final preloaded = widget.preloadedQuotes;
    if (preloaded != null) {
      _previewDecrees = preloaded;
      return;
    }
    _loadingPreview = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadPreview();
    });
  }

  Future<void> _maybeLoadPreview() async {
    final preloaded = widget.preloadedQuotes;
    if (preloaded != null) {
      _previewDecrees = preloaded;
      return;
    }
    setState(() => _loadingPreview = true);
    try {
      final d = await ChannelService(Supabase.instance.client)
          .fetchDecrees(widget.circleId);
      if (!mounted) return;
      setState(() {
        _previewDecrees = d;
        _loadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this channel. Check your connection.';
        _loadingPreview = false;
      });
    }
  }

  Future<void> _fetchCounts() async {
    if (!_isSupabaseChannel) return;
    try {
      final s = await ChannelService(Supabase.instance.client)
          .fetchSummary(widget.circleId);
      if (!mounted || s == null) return;
      setState(() {
        _fetchedMemberCount = s.memberCount;
        _fetchedDecreesCount = s.decreesCount;
      });
    } catch (_) {
      // Header just stays without counts.
    }
  }

  Widget _buildJoinBanner(BuildContext context, AppState state, AppColors c) {
    return Container(
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Preview — Join to add this channel to your feed',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
          FilledButton(
            onPressed: _joining ? null : _onJoinPressed,
            child: _joining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> _onJoinPressed() async {
    final state = AppScope.of(context);
    if (!state.isSignedIn) {
      final ok = await showSignInSheet(context, state);
      if (!ok || !mounted) return;
    }
    setState(() => _joining = true);
    try {
      final code = widget.joinCode;
      if (code != null) {
        await state.joinChannelByCode(code);
      } else {
        await state.joinPublicChannel(widget.circleId);
      }
    } catch (e) {
      if (!mounted) return;
      _showCouldNotJoin();
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _showCouldNotJoin() async {
    final online = await AppScope.of(context).checkConnection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            online ? 'Could not join. Try again.' : offlineActionMessage),
      ),
    );
  }

  // ----------------------------------------------------------------- body

  Widget _buildBody(
    BuildContext context,
    AppState state,
    AppColors c,
    bool preview,
    bool inFeed,
    Circle? circle,
  ) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _error = null;
                  _previewRequested = false;
                }),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (preview) {
      if (_loadingPreview) {
        return const Center(child: CircularProgressIndicator());
      }
      final decrees = _previewDecrees ?? const <ChannelDecreePreview>[];
      if (decrees.isEmpty) {
        return Center(
          child: Text('No decrees in this channel yet.',
              style: TextStyle(color: c.muted)),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: decrees.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, i) => _previewRow(context, state, decrees[i]),
      );
    }

    final quotes = inFeed ? circle!.quotes : const <Quote>[];
    return quotes.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'No decrees in this channel yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: c.muted, height: 1.4),
              ),
            ),
          )
        : ListView.separated(
            // Extra room under the last row so the add button doesn't cover it.
            padding: EdgeInsets.only(bottom: _isManager ? 88 : 24),
            itemCount: quotes.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final quote = quotes[i];
              final due = state.dueInfoFor(quote);
              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QuoteViewScreen(quoteId: quote.id),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 12, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            QuoteTitleBody(text: quote.text),
                            const SizedBox(height: 12),
                            ReadCrowns(
                              done: state.readsTodayFor(quote.id),
                              target: quote.targetPerDay,
                              dueLabel: dueLabelText(context, due),
                              dueColor: dueLabelColor(due, c),
                            ),
                          ],
                        ),
                      ),
                      // Reminders are opt-in per decree.
                      ReminderBellButton(quote: quote),
                    ],
                  ),
                ),
              );
            },
          );
  }

  Widget _previewRow(
    BuildContext context,
    AppState state,
    ChannelDecreePreview d,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuoteViewScreen.preview(
            quoteText: d.text,
            targetPerDay: d.targetPerDay,
            channelId: widget.circleId,
            channelName: widget.channelName ?? 'Channel',
            joinCode: widget.joinCode,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QuoteTitleBody(text: d.text),
            const SizedBox(height: 12),
            ReadCrowns(done: 0, target: d.targetPerDay),
          ],
        ),
      ),
    );
  }

  String _plural(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';
}