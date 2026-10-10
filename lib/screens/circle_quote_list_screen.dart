import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import '../widgets/due_time.dart';
import '../widgets/quote_text.dart';
import '../widgets/read_crowns.dart';
import '../widgets/sign_in_sheet.dart';
import 'quote_view_screen.dart';

/// One channel's decree list — the single channel screen.
///
/// Member mode: bold title/body rows, due status, crowns, tap to read.
///
/// Preview mode (entered from search when not a member): the SAME layout,
/// plus a join banner under the header. Rows are fully tappable — the
/// quote view itself gates decreeing/adding behind joining. Header shows
/// member and decree counts in both modes with proper plurals.
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

  /// Header title override (preview mode, channel not in the feed yet).
  final String? channelName;

  /// Header counts (preview mode). Null → fetched live (joined channels).
  final int? memberCount;
  final int? decreesCount;

  /// Set when the user arrived via a code match; joining uses the code.
  final String? joinCode;

  /// Decrees already fetched (code-match path). Null → fetch on open.
  final List<ChannelDecreePreview>? preloadedQuotes;

  /// True when opened from a channel search result.
  final bool isChannelPreview;

  @override
  State<CircleQuoteListScreen> createState() => _CircleQuoteListScreenState();
}

class _CircleQuoteListScreenState extends State<CircleQuoteListScreen> {
  Timer? _clockTimer;

  // Preview-mode decree list (fetched or preloaded). Null in member mode.
  List<ChannelDecreePreview>? _previewDecrees;
  bool _loadingPreview = false;
  String? _error;
  bool _joining = false;

  // Live counts for joined channels (fetched once).
  bool _countsTried = false;
  int? _fetchedMemberCount;
  int? _fetchedDecreesCount;

  @override
  void initState() {
    super.initState();
    // Rebuild every minute so due/next/overdue labels stay current without
    // needing the user to navigate away and back.
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _maybeLoadPreview();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);

    final circle = state.circleById(widget.circleId);
    final inFeed = circle != null;
    final preview =
        widget.isChannelPreview && !state.isMemberOf(widget.circleId);

    if (preview &&
        _previewDecrees == null &&
        !_loadingPreview &&
        _error == null) {
      _maybeLoadPreview();
    }

    final title = circle?.name ?? widget.channelName ?? 'Channel';
    final memberCount = widget.memberCount ?? _fetchedMemberCount;
    final decreesCount = widget.decreesCount ?? _fetchedDecreesCount;
    final countsLine = (memberCount != null || decreesCount != null)
        ? '${_plural(memberCount ?? 0, 'member', 'members')} · '
            '${_plural(decreesCount ?? 0, 'decree', 'decrees')}'
        : null;

    // Joined (Supabase) channels fetch their live counts once, so members
    // see the same header as searchers. Static-JSON channels skip this.
    if (countsLine == null && inFeed && !_countsTried) {
      _countsTried = true;
      _fetchCounts();
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17)),
            if (countsLine != null)
              Text(countsLine, style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (preview) _buildJoinBanner(context, state, c),
          Expanded(
              child: _buildBody(context, state, c, preview, inFeed, circle)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- preview

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
      // No navigation needed: build() re-runs on notifyListeners and the
      // screen switches itself into member mode.
    } catch (e) {
      if (!mounted) return;
      _showCouldNotJoin();
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  /// Extracted so the SnackBar uses the State's context directly after a
  /// mounted check — satisfies use_build_context_synchronously.
  void _showCouldNotJoin() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not join. Try again.')),
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
          child: Text(_error!,
              textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
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

    // Member mode — the original behaviour, unchanged.
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
            padding: const EdgeInsets.only(bottom: 24),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 18),
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
            // Empty crowns show the decree's daily target, matching how
            // the row will look once joined. No status text (not a member).
            ReadCrowns(done: 0, target: d.targetPerDay),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ utilities

  /// "0 members", "1 member", "2 members" — 0 takes the plural.
  String _plural(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';
}