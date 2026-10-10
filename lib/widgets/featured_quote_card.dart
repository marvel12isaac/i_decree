import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

/// A card that rotates through the app's pre-loaded (not channel, not
/// personal) featured quotes every couple of minutes. Tapping it expands the
/// text only if it was too long to show in full; a quote that already fits
/// isn't tappable. Shows nothing until at least one featured quote has
/// loaded.
class FeaturedQuoteCard extends StatefulWidget {
  const FeaturedQuoteCard({super.key});

  @override
  State<FeaturedQuoteCard> createState() => _FeaturedQuoteCardState();
}

class _FeaturedQuoteCardState extends State<FeaturedQuoteCard> {
  static const _rotateEvery = Duration(minutes: 2);
  static const _collapsedMaxLines = 4;

  late AppState _state;
  Timer? _timer;
  int _index = 0;
  bool _expanded = false;
  final _random = Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = AppScope.of(context);
    _timer ??= Timer.periodic(_rotateEvery, (_) => _rotate());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _rotate() {
    final quotes = _state.featuredQuotes;
    if (!mounted || quotes.length < 2) return;
    var next = _random.nextInt(quotes.length);
    if (next == _index % quotes.length) next = (next + 1) % quotes.length;
    setState(() {
      _index = next;
      _expanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final quotes = _state.featuredQuotes;
    if (quotes.isEmpty) return const SizedBox.shrink();
    final quote = quotes[_index % quotes.length];
    final c = AppColors.of(context);
    final textStyle = quoteStyle(size: 15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.teal.withAlpha(90)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final overflows = _textOverflows(
              quote.text,
              textStyle,
              constraints.maxWidth,
              _collapsedMaxLines,
            );
            final tappable = overflows || _expanded;

            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: c.teal),
                    const SizedBox(width: 6),
                    Text(
                      'FEATURED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: c.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  quote.text,
                  style: textStyle,
                  maxLines: _expanded ? null : _collapsedMaxLines,
                  overflow:
                      _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
                if (quote.reference.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '— ${quote.reference}',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ],
              ],
            );

            if (!tappable) return content;

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  content,
                  const SizedBox(height: 6),
                  Center(
                    child: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Whether [text] would need more than [maxLines] lines at [maxWidth].
bool _textOverflows(
  String text,
  TextStyle style,
  double maxWidth,
  int maxLines,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  return painter.didExceedMaxLines;
}
