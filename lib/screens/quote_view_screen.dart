import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/hold_to_read_button.dart';
import '../widgets/quote_text.dart';
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

  final ScrollController _scroll = ScrollController();
  Timer? _delayTimer;
  bool _delayDone = false;
  bool _atEnd = false;
  bool _joinBusy = false;

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

  Future<void> _complete() async {
    final state = AppScope.of(context);

    if (_previewMode) {
      final joined = await _ensureMember(state);
      if (!joined || !mounted) return;

      // The joined channel's feed now holds the real quote; find it by
      // text and decree THAT, so the read counts server-side too.
      final channel = state.circleById(widget.previewChannelId!);
      Quote? real;
      if (channel != null) {
        for (final q in channel.quotes) {
          if (q.text.trim() == widget.previewText!.trim()) {
            real = q;
            break;
          }
        }
      }
      if (real == null) {
        // Feed not populated yet — fall back to just closing the preview.
        if (mounted) Navigator.of(context).pop();
        return;
      }
      // Capture in a final so type promotion survives the closure below.
      final live = real;

      await state.registerRead(live.id);
      if (!mounted) return;
      final today = state.readsTodayFor(live.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Decreed. $today of ${live.targetPerDay} today.')),
      );
      // Swap this preview for the live quote view.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => QuoteViewScreen(quoteId: live.id)),
      );
      return;
    }

    final quote = state.quoteById(widget.quoteId!);
    if (quote == null) return;
    await state.registerRead(quote.id);
    if (!mounted) return;
    final today = state.readsTodayFor(quote.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
          content: Text('Decreed. $today of ${quote.targetPerDay} today.')),
    );
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
    var quote = _resolveQuote(state);
    if (quote == null) return;

    if (_previewMode) {
      final joined = await _ensureMember(state);
      if (!joined || !mounted) return;
      // Prefer the real quote now that we're a member.
      final channel = state.circleById(widget.previewChannelId!);
      if (channel != null) {
        for (final q in channel.quotes) {
          if (q.text.trim() == widget.previewText!.trim()) {
            quote = q;
            break;
          }
        }
      }
    }

    if (!mounted) return;
    final alreadyAdded =
        state.quotes.any((q) => q.text.trim() == quote!.text.trim());
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

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final quote = _resolveQuote(state);
    if (quote == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    // Check after layout whether the text fits without scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkExtent();
    });

    final unlocked = _delayDone && _atEnd;
    final lockedLabel =
        !_delayDone ? 'Take a moment to decree' : 'Scroll to the end to continue';

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!quote.isCircle)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
          if (quote.isCircle)
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
                    QuoteTitleBody(text: quote.text, size: 24, compact: false),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: HoldToReadButton(
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