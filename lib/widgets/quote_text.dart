import 'package:flutter/material.dart';

import '../theme.dart';

/// Renders a decree: everything before the first line break is a bold
/// title; everything after (with leading blank lines trimmed) is normal
/// body text. If the text has no line break at all, the whole thing is
/// shown as a single bold block instead.
///
/// [compact] (the default, for list rows) caps the title to one line and
/// the body to two, with no gap between them, so a blank line in the source
/// text doesn't leave a visible gap. Set it to false for the full reading
/// screen: both are shown in full, with one consistent gap between them —
/// introduced by this widget, regardless of how the source text separates
/// them.
class QuoteTitleBody extends StatelessWidget {
  const QuoteTitleBody({
    super.key,
    required this.text,
    this.size = 18,
    this.compact = true,
  });

  final String text;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final breakAt = text.indexOf('\n');
    final bold = quoteStyle(size: size).copyWith(fontWeight: FontWeight.w700);

    if (breakAt < 0) {
      return Text(
        text,
        maxLines: compact ? 3 : null,
        overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
        style: bold,
      );
    }

    final title = text.substring(0, breakAt).trim();
    final body = text.substring(breakAt + 1).trimLeft();

    return SizedBox(
      // Full width so no ancestor's center alignment can shift the block;
      // the texts always sit hard-left.
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
          maxLines: compact ? 1 : null,
          overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
          style: bold,
        ),
        if (!compact && body.isNotEmpty) SizedBox(height: size * 0.9),
          Text(
            body,
            maxLines: compact ? 2 : null,
            overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
            style: quoteStyle(size: size),
          ),
        ],
      ),
    );
  }
}
