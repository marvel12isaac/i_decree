import 'package:flutter/material.dart';

import '../theme.dart';

/// Renders a decree for a list row: everything before the first line break
/// is a bold, one-line title; everything after (with leading blank lines
/// trimmed, so a blank separator line doesn't leave a visible gap) is normal
/// body text directly beneath it. If the text has no line break at all, the
/// whole thing is shown as a single bold block instead.
class QuoteTitleBody extends StatelessWidget {
  const QuoteTitleBody({super.key, required this.text, this.size = 18});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final breakAt = text.indexOf('\n');
    final bold = quoteStyle(size: size).copyWith(fontWeight: FontWeight.w700);

    if (breakAt < 0) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: bold,
      );
    }

    final title = text.substring(0, breakAt).trim();
    final body = text.substring(breakAt + 1).trimLeft();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold),
        if (body.isNotEmpty)
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: quoteStyle(size: size),
          ),
      ],
    );
  }
}
