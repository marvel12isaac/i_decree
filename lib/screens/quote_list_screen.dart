import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'quote_editor_screen.dart';
import 'quote_view_screen.dart';

/// The Personal space: the user's own quotes, with streak and today's
/// progress on each. Swipe left to delete.
///
/// (Stage 2 adds Circles: their quote lists will look the same but come from
/// a hosted file and can't be edited or deleted by members.)
class QuoteListScreen extends StatelessWidget {
  const QuoteListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final quotes = state.quotes;

    return Scaffold(
      appBar: AppBar(title: const Text('Personal')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuoteEditorScreen()),
        ),
        backgroundColor: Palette.deep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add a decree'),
      ),
      body: quotes.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: quotes.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) => _QuoteRow(quote: quotes[i]),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'No decrees yet. Add the first one you want to read every day.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Palette.muted, height: 1.4),
        ),
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
    final streak = state.quoteStreak(quote.id);
    final today = state.readsTodayFor(quote.id);
    final complete = today >= quote.targetPerDay;

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
              Text(
                quote.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: quoteStyle(size: 18),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    size: 18,
                    color: streak > 0 ? Palette.gold : Palette.muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    streak > 0 ? '$streak-day streak' : 'No streak yet',
                    style: const TextStyle(color: Palette.muted, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '$today of ${quote.targetPerDay} today',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: complete ? FontWeight.w600 : FontWeight.w400,
                      color: complete ? Palette.sage : Palette.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
