import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../fx.dart';
import '../models.dart';
import '../services/channel_service.dart';
import '../widgets/fx_widgets.dart';
import '../widgets/hold_to_read_button.dart';
import '../widgets/quote_text.dart';
import '../widgets/read_crowns.dart';
import '../widgets/reminder_bell.dart';
import '../widgets/report_dialog.dart';
import '../theme.dart';
import '../widgets/sign_in_sheet.dart';
import 'quote_editor_screen.dart';

/// Shows one quote. The Read button unlocks after a short fixed delay and,
/// for quotes long enough to scroll, only once the user reaches the end.
///
/// Preview mode ([QuoteViewScreen.preview]): opened from a channel search
/// result by a non-member. The quote is fully readable, but the two
/// actions that need membership — decreeing and adding to My Decrees —
/// trigger the join flow first (sign-in sheet if needed), then the action
/// completes. After a preview decree, the screen replaces itself with the
/// real, live quote from the joined channel.
class QuoteViewScreen extends StatefulWidget {
  const QuoteViewScreen({super.key, required this.quoteId})
      : previewText = null,
        previewTarget = 1,
        previewChannelId = null,
        previewChannelName = null,
        previewJoinCode = null;

  /// Preview of a channel decree the user hasn't joined yet.
  const QuoteViewScreen.preview({
    super.key,
    required String quoteText,
    required int targetPerDay,
    required String channelId,
    required String channelName,
    String? joinCode,
  })  : quoteId = null,
        previewText = quoteText,
        previewTarget = targetPerDay,
        previewChannelId = channelId,
        previewChannelName = channelName,
        previewJoinCode = joinCode;

  final String? quoteId;

  final String? previewText;
  final int previewTarget;
  final String? previewChannelId;
  final String? previewChannelName;
  final String? previewJoinCode;

  @override
  State<QuoteViewScreen> createState() => _QuoteViewScreenState();
}

class _QuoteViewScreenState extends State<QuoteViewScreen> {
  static const Duration _unlockDelay = Duration(seconds: 5);

  /// How long the "Decreed" panel stays up before the screen closes
  /// (shorter in Reduced mode, skipped in Off mode).
  static const Duration _decreedPanelTime = Duration(milliseconds: 700);

  final ScrollController _scroll = ScrollController();
  Timer? _delayTimer;
  bool _delayDone = false;
  bool _atEnd = false;
  bool _joinBusy = false;

  /// Set right after a read completes: today's read count, shown in the
  /// "Decreed" panel in place of the hold button.
  int? _decreedCount;

  // The user's role in this decree's channel (for managers' edit options).
  // Null until known; the channel icons stay hidden until then so they
  // never flash from member options to manager options.
  String? _myRole;
  bool _roleRequested = false;
  bool get _isManager => _myRole == 'owner' || _myRole == 'admin';

  bool get _previewMode => widget.previewText != null;

  /// The quote this screen shows: the real one, or a synthetic preview
  /// quote built from the passed-in content.
  Quote? _resolveQuote(AppState state) {
    if (_previewMode) {
      return Quote(
        id: 'preview',
        text: widget.previewText!,
        notifBase: 0,
        createdAt: DateTime.now(),
        targetPerDay: widget.previewTarget,
        remindersOn: false,
        isCircle: true,
        circleId: widget.previewChannelId,
      );
    }
    return state.quoteById(widget.quoteId!);
  }

  @override
  void initState() {
    super.initState();
    _delayTimer = Timer(_unlockDelay, () {
      if (mounted) setState(() => _delayDone = true);
    });
    _scroll.addListener(_checkExtent);
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Once the user has reached the end (or there's nothing to scroll), stay
  /// unlocked.
  void _checkExtent() {
    if (_atEnd || !_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.maxScrollExtent <= 0 || p.pixels >= p.maxScrollExtent - 8) {
      setState(() => _atEnd = true);
    }
  }

  // ------------------------------------------------------------ join gate

  /// Makes sure the user is a member of the preview channel, running the
  /// sign-in sheet and join flow as needed. Returns true when membership
  /// is confirmed.
  Future<bool> _ensureMember(AppState state) async {
    final channelId = widget.previewChannelId!;
    if (state.isMemberOf(channelId)) return true;

    if (!state.isSignedIn) {
      final ok = await showSignInSheet(context, state);
      if (!ok || !mounted) return false;
    }

    setState(() => _joinBusy = true);
    try {
      final code = widget.previewJoinCode;
      if (code != null) {
        await state.joinChannelByCode(code);
      } else {
        await state.joinPublicChannel(channelId);
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join. Try again.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _joinBusy = false);
    }
  }

  // -------------------------------------------------------------- actions

  /// The real, live copy of the previewed decree once the user has joined
  /// (matched by text; the feed holds the real ids).
  Quote? _liveQuoteForPreview(AppState state) {
    final channel = state.circleById(widget.previewChannelId!);
    if (channel == null) return null;
    for (final q in channel.quotes) {
      if (q.text.trim() == widget.previewText!.trim()) return q;
    }
    return null;
  }

  /// "Join to decree": a non-member can't decree, so this runs the join flow
  /// (sign-in if needed) and then swaps to the real decree view, where the
  /// hold button works. No read is counted automatically.
  Future<void> _joinToDecree() async {
    final state = AppScope.of(context);
    final joined = await _ensureMember(state);
    if (!joined || !mounted) return;
    final live = _liveQuoteForPreview(state);
    if (live == null) {
      // The feed hasn't filled in yet: close the preview; they are joined.
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      FxPageRoute(builder: (_) => QuoteViewScreen(quoteId: live.id)),
    );
  }

  Future<void> _complete() async {
    final state = AppScope.of(context);

    final quote = state.quoteById(widget.quoteId!);
    if (quote == null) return;
    await state.registerRead(quote.id);
    if (!mounted) return;
    // Milestone check (streak of 7, 30, 100, or the very first read).
    Fx.afterRead(context, state);
    final today = state.readsTodayFor(quote.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
          content: Text('Decreed. $today of ${quote.targetPerDay} today.')),
    );
    if (!Fx.isOff) {
      // Show the "Decreed" panel with the new crown popping in, then close.
      setState(() => _decreedCount = today);
      await Future<void>.delayed(Fx.dur(_decreedPanelTime));
      if (!mounted) return; // the user already left
    }
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _edit() async {
    final quote = AppScope.of(context).quoteById(widget.quoteId!);
    if (quote == null) return;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuoteEditorScreen(quote: quote)),
    );
    if (deleted == true && mounted) Navigator.of(context).pop();
  }

  /// Opens the editor pre-filled, so the user can adjust it before it's
  /// saved as a new personal decree. In preview mode, membership is
  /// required first — the join flow runs, then the editor opens.
  Future<void> _addToMyDecrees() async {
    final state = AppScope.of(context);
    final quote = _resolveQuote(state);
    if (quote == null) return;

    if (!mounted) return;
    final alreadyAdded =
        state.quotes.any((q) => q.text.trim() == quote.text.trim());
    if (alreadyAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already added to My Decrees.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QuoteEditorScreen(prefill: quote)),
    );
  }

  // ----------------------------------------------- manager role and editing

  Future<void> _loadRole(String channelId) async {
    try {
      final role =
          await ChannelService(Supabase.instance.client).fetchMyRole(channelId);
      if (!mounted) return;
      setState(() => _myRole = role);
      AppScope.of(context).cacheRole(channelId, role);
    } catch (e) {
      // Offline: fall back to the member options so the icons still appear.
      debugPrint('Could not load channel role: $e');
      if (mounted) setState(() => _myRole ??= 'member');
    }
  }

  /// Managers edit one channel decree in place (its id, and so members'
  /// read history and reminder choices, are kept).
  Future<void> _editChannelDecree(Quote quote) async {
    final seed = Quote(
      id: 'draft-edit',
      text: quote.text,
      notifBase: 0,
      createdAt: DateTime.now(),
      targetPerDay: quote.targetPerDay,
      windowStartMin: quote.windowStartMin,
      windowEndMin: quote.windowEndMin,
      remindersOn: false,
    );
    final draft = await Navigator.of(context).push<DecreeDraft>(
      MaterialPageRoute(builder: (_) => QuoteEditorScreen.draft(seed: seed)),
    );
    if (draft == null || !mounted) return;

    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ChannelService(Supabase.instance.client).updateDecree(
        quote.id,
        text: draft.text,
        targetPerDay: draft.targetPerDay,
        windowStartMin: draft.windowStartMin,
        windowEndMin: draft.windowEndMin,
      );
      await state.refreshJoinedChannels();
      messenger.showSnackBar(const SnackBar(content: Text('Decree updated.')));
    } catch (e) {
      debugPrint('Could not update decree: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update the decree. Try again.')),
      );
    }
  }

  Future<void> _onMenu(String value, Quote quote) async {
    switch (value) {
      case 'edit':
        await _editChannelDecree(quote);
        break;
      case 'reminder':
        await toggleChannelReminder(context, quote);
        break;
      case 'add':
        await _addToMyDecrees();
        break;
      case 'report':
        await _report(quote);
        break;
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- report

  ReportTarget? _reportTarget(Quote quote) {
    // Only members can report: a not-yet-joined preview has no report option.
    if (_previewMode) return null;
    final channelId = quote.circleId;
    if (channelId == null) return null;
    return ReportTarget.decree(channelId: channelId, quoteId: quote.id);
  }

  Future<void> _report(Quote quote) async {
    final target = _reportTarget(quote);
    if (target == null) return;
    await showReportDialog(context, AppScope.of(context), target);
  }

  // ---------------------------------------------------------------- build

  /// Preview mode: decreeing and copying need membership, so both actions say
  /// "Join" and run the join flow first.
  Widget _buildJoinActions(BuildContext context) {
    final c = AppColors.of(context);
    final name = widget.previewChannelName ?? 'this channel';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Join $name to start decreeing.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _joinBusy ? null : _joinToDecree,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(_joinBusy ? 'Joining…' : 'Join to decree'),
        ),
      ],
    );
  }

  /// Replaces the hold button for a moment after a read: "Decreed" plus
  /// today's crowns, with the crown just earned popping in. Same height as
  /// the button so nothing jumps.
  Widget _buildDecreedPanel(BuildContext context, Quote quote, int today) {
    final c = AppColors.of(context);
    final target = quote.targetPerDay;
    final popIndex = (today >= 1 && today <= target) ? today - 1 : null;
    return Container(
      height: 60,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: c.teal.withAlpha(31),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: c.teal),
          const SizedBox(width: 8),
          Text(
            'Decreed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.teal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ReadCrowns(
              done: today,
              target: target,
              size: 20,
              popIndex: popIndex,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final quote = _resolveQuote(state);
    if (quote == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final decreedToday = state.readsTodayFor(quote.id) >= quote.targetPerDay;

    // Check after layout whether the text fits without scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkExtent();
    });

    // Managers get their edit options in the menu; look up the role once.
    final channelId = quote.circleId;
    if (quote.isCircle && !_previewMode && channelId != null) {
      // A cached role means the right icons show from the very first frame.
      _myRole ??= state.roleFor(channelId);
      if (!_roleRequested) {
        _roleRequested = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _loadRole(channelId));
      }
    }
    final roleKnown = _previewMode || _myRole != null;
    final managerMenu = quote.isCircle && !_previewMode && _isManager;

    final unlocked = _delayDone && _atEnd;
    final lockedLabel =
        !_delayDone ? 'Take a moment to decree' : 'Scroll to the end to continue';

    final decreedCount = _decreedCount;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!quote.isCircle)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
          // Members: bell and add-to-My-Decrees stay on the bar. A not-yet-joined
          // preview has neither: it gets labelled Join buttons below instead.
          if (quote.isCircle && roleKnown && !managerMenu && !_previewMode) ...[
            ReminderBellButton(quote: quote),
            IconButton(
              tooltip: 'Add to My Decrees',
              icon: _joinBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.playlist_add),
              onPressed: _joinBusy ? null : _addToMyDecrees,
            ),
          ],
          // Channel owners and admins: edit, reminders, add-to-My-Decrees and
          // report all live in the menu. Everyone else just gets Report.
          if (quote.isCircle &&
              roleKnown &&
              (managerMenu || _reportTarget(quote) != null))
            PopupMenuButton<String>(
              onSelected: (value) => _onMenu(value, quote),
              itemBuilder: (_) => [
                if (managerMenu) ...[
                  _menuItem('edit', Icons.edit_outlined, 'Edit decree'),
                  _menuItem(
                    'reminder',
                    quote.remindersOn
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_none,
                    quote.remindersOn ? 'Turn off reminders' : 'Remind me',
                  ),
                  _menuItem('add', Icons.playlist_add, 'Add to My Decrees'),
                ],
                if (_reportTarget(quote) != null)
                  _menuItem('report', Icons.flag_outlined, 'Report this decree'),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The decree text fades in and rises slightly, once per
                    // time the screen opens.
                    FadeSlideIn(
                      child: QuoteTitleBody(
                          text: quote.text, size: 24, compact: false),
                    ),
                    if (decreedToday) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 18, color: AppColors.of(context).teal),
                          const SizedBox(width: 6),
                          Text(
                            'Decreed today ✓',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.of(context).teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: _previewMode
                  ? _buildJoinActions(context)
                  : decreedCount != null
                      ? _buildDecreedPanel(context, quote, decreedCount)
                      : HoldToReadButton(
                          unlocked: unlocked,
                          lockedLabel: lockedLabel,
                          onCompleted: _complete,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}