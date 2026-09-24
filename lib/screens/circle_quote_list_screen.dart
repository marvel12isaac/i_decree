import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/read_bolts.dart';
import 'quote_view_screen.dart';

/// One Circle's quote list: same look as the personal list, but read-only —
/// no add button, no swipe-to-delete, since the content comes from the
/// hosted file and members can't edit it.
///
/// Each decree shows today's read progress as lightning bolts, right-aligned
/// under the text.
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
                        Text(
                          quote.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: quoteStyle(size: 18),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ReadBolts(
                            done: state.readsTodayFor(quote.id),
                            target: quote.targetPerDay,
                          ),
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
