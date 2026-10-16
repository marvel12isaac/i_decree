import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/due_time.dart';
import '../widgets/featured_quote_card.dart';
import '../widgets/quote_text.dart';
import '../widgets/read_crowns.dart';
import 'quote_editor_screen.dart';
import 'quote_view_screen.dart';

/// My Decrees: the user's own quotes. Each row shows the text as a bold
/// title with normal body text under it, then a due/next/last-read status
/// with today's read progress as crowns. Swipe left to reveal a trash
/// button; tapping it asks for confirmation before deleting.
///
/// Rows follow the same order as Home's channels (see
/// AppState.quotesByDue). The Featured card above the list is not part of
/// that order.
///
/// (Channels have the same list, but it comes from a hosted file and can't be
/// edited or deleted by members.)
class QuoteListScreen extends StatefulWidget {
  const QuoteListScreen({super.key});

  @override
  State<QuoteListScreen> createState() => _QuoteListScreenState();
}

class _QuoteListScreenState extends State<QuoteListScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    // Rebuild every minute so due/next/overdue labels stay current without
    // needing the user to navigate away and back.
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
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
    final quotes = state.quotesByDue();

    return Scaffold(
      appBar: AppBar(title: const Text('My Decrees')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuoteEditorScreen()),
        ),
        backgroundColor: Palette.deep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Decree'),
      ),
      body: Column(
        children: [
          const FeaturedQuoteCard(),
          Expanded(
            child: quotes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'No decrees yet. Add the first one you want to read every day.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 16, color: c.muted, height: 1.4),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: quotes.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) => _QuoteRow(quote: quotes[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    final due = state.dueInfoFor(quote);

    return _SwipeToDelete(
      key: ValueKey(quote.id),
      // Double check: swiping only reveals the trash button; tapping it opens
      // the usual confirmation dialog.
      onDelete: () async {
        final ok = await confirmDelete(context);
        if (ok != true) return false;
        state.deleteQuote(quote.id);
        return true;
      },
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuoteViewScreen(quoteId: quote.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
      ),
    );
  }
}

/// Swipe a row left to reveal a round trash button behind it. Nothing is
/// deleted by the swipe itself: tapping the button runs [onDelete] (which
/// shows the confirmation dialog and returns true if the row was deleted).
/// Tapping the row, or cancelling the dialog, closes it again.
class _SwipeToDelete extends StatefulWidget {
  const _SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final Future<bool> Function() onDelete;

  @override
  State<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<_SwipeToDelete> {
  static const double _revealWidth = 96;

  double _dx = 0;
  bool _dragging = false;
  bool _isOpen = false;

  void _setOpen(bool open) {
    setState(() {
      _isOpen = open;
      _dx = open ? -_revealWidth : 0;
      _dragging = false;
    });
  }

  Future<void> _confirmDelete() async {
    final deleted = await widget.onDelete();
    if (!deleted && mounted) _setOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      children: [
        // The trash button sits behind the row and is uncovered by the swipe.
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: IgnorePointer(
                ignoring: !_isOpen,
                child: Material(
                  color: Palette.danger.withValues(alpha: 0.15),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _confirmDelete,
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.delete_outline, color: Palette.danger),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (d) => setState(() {
            _dx = (_dx + d.delta.dx).clamp(-_revealWidth, 0.0).toDouble();
          }),
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            _setOpen(v < -300 || (v <= 300 && _dx < -_revealWidth / 2));
          },
          onTap: _isOpen ? () => _setOpen(false) : null,
          child: AnimatedContainer(
            duration:
                _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            color: c.background,
            child: AbsorbPointer(absorbing: _isOpen, child: widget.child),
          ),
        ),
      ],
    );
  }
}