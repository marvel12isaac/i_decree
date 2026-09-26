import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/due_time.dart';
import '../widgets/quote_text.dart';
import '../widgets/read_crowns.dart';
import 'quote_view_screen.dart';

/// One Circle's quote list: same look as the personal list, but read-only —
/// no add button, no swipe-to-delete, since the content comes from the
/// hosted file and members can't edit it.
///
/// Each row shows the text as a bold title with normal body text under it,
/// then a due/next/last-read status with today's read progress as crowns.
class CircleQuoteListScreen extends StatelessWidget {
  const CircleQuoteListScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);

    final circle = state.circleById(circleId);
    final quotes = circle?.quotes ?? const <Quote>[];

    return Scaffold(
      appBar: AppBar(title: Text(circle?.name ?? 'Circle')),
      body: quotes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'No decrees in this circle yet.',
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
            ),
    );
  }
}
