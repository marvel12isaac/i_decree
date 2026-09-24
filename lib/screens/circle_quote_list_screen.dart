import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'quote_view_screen.dart';

/// One Circle's quote list: same look as the personal list, but read-only —
/// no add button, no swipe-to-delete, since the content comes from the
/// hosted file and members can't edit it.
class CircleQuoteListScreen extends StatelessWidget {
  const CircleQuoteListScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doneColor = isDark ? c.teal : Palette.sage;

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
                final streak = state.quoteStreak(quote.id);
                final today = state.readsTodayFor(quote.id);
                final complete = today >= quote.targetPerDay;

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
                        Row(
                          children: [
                            Icon(
                              Icons.local_fire_department_outlined,
                              size: 18,
                              color: streak > 0 ? c.flame : c.muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              streak > 0 ? '$streak-day streak' : 'No streak yet',
                              style: TextStyle(color: c.muted, fontSize: 14),
                            ),
                            const Spacer(),
                            Text(
                              '$today of ${quote.targetPerDay} today',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    complete ? FontWeight.w600 : FontWeight.w400,
                                color: complete ? doneColor : c.muted,
                              ),
                            ),
                          ],
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
