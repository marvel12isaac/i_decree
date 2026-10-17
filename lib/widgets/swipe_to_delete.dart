import 'package:flutter/material.dart';

import '../theme.dart';

/// Swipe a row left to reveal a round trash button behind it. Nothing is
/// removed by the swipe itself: tapping the button runs [onDelete], which
/// returns true if the row was removed (false closes the row again).
/// Tapping the row, or a false result, closes it. Only one row is open at a
/// time: pass the SAME [openRow] notifier to every row in a list.
///
/// Used by My Decrees (confirm dialog, then delete) and by a channel's Edit
/// decrees (stages the removal until Save).
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.id,
    required this.openRow,
    required this.child,
    required this.onDelete,
  });

  final String id;
  final ValueNotifier<String?> openRow;
  final Widget child;
  final Future<bool> Function() onDelete;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  static const double _revealWidth = 96;

  double _dx = 0;
  bool _dragging = false;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    widget.openRow.addListener(_onOpenRowChanged);
  }

  @override
  void dispose() {
    widget.openRow.removeListener(_onOpenRowChanged);
    super.dispose();
  }

  /// Another row opened: close this one.
  void _onOpenRowChanged() {
    if (_isOpen && widget.openRow.value != widget.id && mounted) {
      setState(() {
        _isOpen = false;
        _dx = 0;
        _dragging = false;
      });
    }
  }

  void _setOpen(bool open) {
    setState(() {
      _isOpen = open;
      _dx = open ? -_revealWidth : 0;
      _dragging = false;
    });
    if (open) {
      widget.openRow.value = widget.id;
    } else if (widget.openRow.value == widget.id) {
      widget.openRow.value = null;
    }
  }

  Future<void> _confirmDelete() async {
    final deleted = await widget.onDelete();
    if (!deleted && mounted) _setOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      children: [
        // The trash button sits behind the row and is uncovered by the swipe.
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: IgnorePointer(
                ignoring: !_isOpen,
                child: Material(
                  color: Palette.danger.withValues(alpha: 0.15),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _confirmDelete,
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.delete_outline, color: Palette.danger),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The gesture detector lives INSIDE the sliding row, so the strip the
        // row slides away from belongs only to the trash button.
        AnimatedContainer(
          duration:
              _dragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(_dx, 0, 0),
          // A Material (not just a colour) so taps on the row still show
          // their ripple on top of the background.
          child: Material(
            color: c.background,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) {
                // Starting to swipe a row closes any other row that is open.
                final open = widget.openRow.value;
                if (open != null && open != widget.id) {
                  widget.openRow.value = null;
                }
                setState(() => _dragging = true);
              },
              onHorizontalDragUpdate: (d) => setState(() {
                _dx = (_dx + d.delta.dx).clamp(-_revealWidth, 0.0).toDouble();
              }),
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                _setOpen(v < -300 || (v <= 300 && _dx < -_revealWidth / 2));
              },
              onTap: _isOpen ? () => _setOpen(false) : null,
              child: AbsorbPointer(absorbing: _isOpen, child: widget.child),
            ),
          ),
        ),
      ],
    );
  }
}