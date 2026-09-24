import 'package:flutter/material.dart';

import '../theme.dart';

/// Today's read progress for one decree: one lightning bolt per required
/// read. A filled bolt is a read already done, an outlined bolt is a read
/// still to do. Reads beyond the target keep every bolt filled and add a
/// small "+N" badge. Wraps onto extra lines for high targets.
///
/// Place it inside an [Align] with [Alignment.centerRight] to right-align it.
class ReadBolts extends StatelessWidget {
  const ReadBolts({
    super.key,
    required this.done,
    required this.target,
    this.size = 20,
  });

  /// Reads completed today.
  final int done;

  /// Reads required today (the decree's target per day).
  final int target;

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final total = target < 1 ? 1 : target;
    final filled = done > total ? total : done;
    final extra = done > total ? done - total : 0;

    return Semantics(
      label: 'Read $done of $total times today',
      child: ExcludeSemantics(
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            for (var i = 0; i < total; i++)
              Icon(
                i < filled ? Icons.bolt : Icons.bolt_outlined,
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
      ),
    );
  }
}
