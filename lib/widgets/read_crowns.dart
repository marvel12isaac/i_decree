import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme.dart';

/// Today's read progress for one decree, combined with its due status on one
/// line: the due/next/last-read text on the left, one crown per required
/// read on the right. A filled crown is a read already done; an outlined
/// crown is a read still to do. Reads beyond the target keep every crown
/// filled and add a small "+N" badge, where N is how many times over target
/// the decree has been read today. If the crowns don't fit next to the
/// text, they wrap onto their own line below it — the text never wraps.
class ReadCrowns extends StatelessWidget {
  const ReadCrowns({
    super.key,
    required this.done,
    required this.target,
    this.dueLabel,
    this.dueColor,
    this.size = 20,
  });

  /// Reads completed today.
  final int done;

  /// Reads required today (the decree's target per day).
  final int target;

  /// Optional due/next/last-read text shown to the left of the crowns.
  final String? dueLabel;
  final Color? dueColor;

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final total = target < 1 ? 1 : target;
    final filled = done > total ? total : done;
    final extra = done > total ? done - total : 0;

    final crowns = Expanded(
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 3,
        runSpacing: 3,
        children: [
          for (var i = 0; i < total; i++)
            Icon(
              Symbols.crown,
              fill: i < filled ? 1 : 0,
              size: size,
              color: i < filled ? c.teal : c.ring,
            ),
          if (extra > 0)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.teal.withAlpha(46),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '+$extra',
                style: TextStyle(
                  color: c.teal,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      label: 'Read $done of $total times today',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: dueLabel == null
              ? [crowns]
              : [
                  Text(
                    dueLabel!,
                    style: TextStyle(fontSize: 12, color: dueColor ?? c.muted),
                  ),
                  const SizedBox(width: 8),
                  crowns,
                ],
        ),
      ),
    );
  }
}
