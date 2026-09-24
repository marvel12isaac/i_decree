import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/read_bolts.dart';
import '../widgets/hold_to_read_button.dart';
import 'quote_editor_screen.dart';

/// Shows one quote. The Read button unlocks after a short fixed delay and,
/// for quotes long enough to scroll, only once the user reaches the end.
/// The delay timer runs quietly in the background; it only stops people from
/// tapping straight through.
class QuoteViewScreen extends StatefulWidget {
  const QuoteViewScreen({super.key, required this.quoteId});

  final String quoteId;

  @override
  State<QuoteViewScreen> createState() => _QuoteViewScreenState();
}

class _QuoteViewScreenState extends State<QuoteViewScreen> {
  static const Duration _unlockDelay = Duration(seconds: 5);

  final ScrollController _scroll = ScrollController();
  Timer? _delayTimer;
  bool _delayDone = false;
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _delayTimer = Timer(_unlockDelay, () {
      if (mounted) setState(() => _delayDone = true);
    });
    _scroll.addListener(_checkExtent);
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Once the user has reached the end (or there's nothing to scroll), stay
  /// unlocked.
  void _checkExtent() {
    if (_atEnd || !_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.maxScrollExtent <= 0 || p.pixels >= p.maxScrollExtent - 8) {
      setState(() => _atEnd = true);
    }
  }

  Future<void> _complete() async {
    final state = AppScope.of(context);
    final quote = state.quoteById(widget.quoteId);
    if (quote == null) return;
    await state.registerRead(quote.id);
    if (!mounted) return;
    final today = state.readsTodayFor(quote.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Read. $today of ${quote.targetPerDay} today.')),
    );
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _edit() async {
    final quote = AppScope.of(context).quoteById(widget.quoteId);
    if (quote == null) return;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuoteEditorScreen(quote: quote)),
    );
    if (deleted == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final quote = state.quoteById(widget.quoteId);
    if (quote == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    // Check after layout whether the text fits without scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkExtent();
    });

    final streak = state.quoteStreak(quote.id);
    final today = state.readsTodayFor(quote.id);
    final unlocked = _delayDone && _atEnd;    
    final lockedLabel =
        !_delayDone ? 'Take a moment to decree' : 'Scroll to the end to continue';

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!quote.isCircle)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quote.text, style: quoteStyle(size: 24)),
                    const SizedBox(height: 32),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ReadBolts(
                        done: today,
                        target: quote.targetPerDay,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: HoldToReadButton(
                unlocked: unlocked,
                lockedLabel: lockedLabel,
                onCompleted: _complete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
