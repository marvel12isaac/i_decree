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
/// with today's read progress as crowns. Swipe left to delete.
///
/// (Circles have the same list, but it comes from a hosted file and can't be
/// edited or deleted by members.)
class QuoteListScreen extends StatelessWidget {
  const QuoteListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    final quotes = state.quotes;

    return Scaffold(
      appBar: AppBar(title: const Text('My Decrees')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuoteEditorScreen()),
        ),
        backgroundColor: Palette.deep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add a decree'),
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

    return Dismissible(
      key: ValueKey(quote.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDelete(context),
      onDismissed: (_) => state.deleteQuote(quote.id),
      background: Container(
        color: Palette.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
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
