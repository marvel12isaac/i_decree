import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/due_time.dart';
import '../widgets/featured_quote_card.dart';
import '../widgets/quote_text.dart';
import '../widgets/read_crowns.dart';
import '../widgets/swipe_to_delete.dart';
import '../widgets/toast.dart';
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

  /// The id of the row whose trash button is showing (null = none). Shared by
  /// all rows so only one can be open at a time.
  final ValueNotifier<String?> _openRow = ValueNotifier<String?>(null);

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
    _openRow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    final quotes = state.quotesByDue();

    return Scaffold(
      appBar: AppBar(title: const Text('My Decrees')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a decree',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuoteEditorScreen()),
        ),
        backgroundColor: Palette.deep,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
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
                    itemBuilder: (context, i) =>
                        _QuoteRow(quote: quotes[i], openRow: _openRow),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote, required this.openRow});

  final Quote quote;
  final ValueNotifier<String?> openRow;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    final due = state.dueInfoFor(quote);

    return SwipeToDelete(
      key: ValueKey(quote.id),
      id: quote.id,
      openRow: openRow,
      // Double check: swiping only reveals the trash button; tapping it opens
      // the usual confirmation dialog.
      onDelete: () async {
        final ok = await confirmDelete(context);
        if (ok != true) return false;
        state.deleteQuote(quote.id);
        showToast('Decree deleted.');
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