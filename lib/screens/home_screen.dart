import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/due_time.dart';
import 'circle_quote_list_screen.dart';
import 'quote_list_screen.dart';
import 'quote_view_screen.dart';
import 'streak_calendar_screen.dart';

/// Home: the app icon and theme toggle, a search field, the daily streak
/// card, then a chat-style list of spaces (Personal, then one row per
/// Circle). Typing in the search field swaps the list for matching circles
/// and decrees.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _search.text.trim();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(state, isDark, c),
              _buildSearchField(c),
              if (query.isEmpty)
                ..._buildHome(context, state, c)
              else
                ..._buildResults(context, state, c, query),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- header

  Widget _buildHeader(AppState state, bool isDark, AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/icons/logo_mark.png',
            width: 40,
            height: 40,
            color: c.text,
            colorBlendMode: BlendMode.srcIn,
            semanticLabel: 'iDecree',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
              onPressed: () => state.setThemeMode(
                isDark ? ThemeMode.light : ThemeMode.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- search

  Widget _buildSearchField(AppColors c) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c.line),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: c.muted),
          prefixIcon: Icon(Icons.search, color: c.muted),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close, color: c.muted),
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.teal),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildResults(
    BuildContext context,
    AppState state,
    AppColors c,
    String query,
  ) {
    final q = query.toLowerCase();

    final circles = state.circles
        .where((circle) => circle.name.toLowerCase().contains(q))
        .toList();

    final hits = <_Hit>[];
    for (final quote in state.quotes) {
      if (quote.text.toLowerCase().contains(q)) {
        hits.add(_Hit(quote, 'My Decrees'));
      }
    }
    for (final circle in state.circles) {
      for (final quote in circle.quotes) {
        if (quote.text.toLowerCase().contains(q)) {
          hits.add(_Hit(quote, circle.name));
        }
      }
    }

    if (circles.isEmpty && hits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
          child: Center(
            child: Text(
              'Nothing matches "$query".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: c.muted),
            ),
          ),
        ),
      ];
    }

    return [
      if (circles.isNotEmpty) ...[
        const _SectionLabel('Circles'),
        for (final circle in circles) ...[
          _circleRow(context, state, c, circle, highlight: query),
          const Divider(),
        ],
      ],
      if (hits.isNotEmpty) ...[
        const _SectionLabel('Decrees'),
        for (final hit in hits) ...[
          _DecreeHitRow(hit: hit, query: query),
          const Divider(),
        ],
      ],
    ];
  }

  // ------------------------------------------------------------------- home

  List<Widget> _buildHome(BuildContext context, AppState state, AppColors c) {
    final personalCount = state.quotes.length;

    return [
      _buildStreakCard(context, state, c),
      if (!state.reminders.supported)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text(
            'Reminders work in the Android app. Web reminders come later.',
            style: TextStyle(color: c.muted),
          ),
        ),
      const Divider(),
      _SpaceRow(
        icon: Icons.person_outline,
        title: 'My Decrees',
        subtitle: personalCount == 0
            ? 'No decrees yet'
            : _preview(state.quotes.first.text),
        unread: state.unreadCountFor(state.quotes),
        dueLabel: dueLabelText(context, state.spaceDueInfo(state.quotes)),
        dueColor: dueLabelColor(state.spaceDueInfo(state.quotes), c),
        personal: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuoteListScreen()),
        ),
      ),
      const Divider(),
      if (state.circles.isNotEmpty) const _SectionLabel('Circles'),
      for (final circle in state.circles) ...[
        _circleRow(context, state, c, circle),
        const Divider(),
      ],
    ];
  }

  String _circleSubtitle(Circle circle) =>
      circle.quotes.isEmpty ? 'No decrees yet' : _preview(circle.quotes.first.text);

  void _openCircle(BuildContext context, Circle circle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CircleQuoteListScreen(circleId: circle.id),
      ),
    );
  }

  /// One circle's Home row, with its due/next/last-read status computed once.
  Widget _circleRow(
    BuildContext context,
    AppState state,
    AppColors c,
    Circle circle, {
    String highlight = '',
  }) {
    final due = state.spaceDueInfo(circle.quotes);
    return _SpaceRow(
      icon: Icons.groups_outlined,
      title: circle.name,
      subtitle: _circleSubtitle(circle),
      unread: state.unreadCountFor(circle.quotes),
      dueLabel: dueLabelText(context, due),
      dueColor: dueLabelColor(due, c),
      highlight: highlight,
      onTap: () => _openCircle(context, circle),
    );
  }

  Widget _buildStreakCard(BuildContext context, AppState state, AppColors c) {
    final streak = state.dailyStreak();
    final best = state.bestDaily > streak ? state.bestDaily : streak;
    final readsToday = state.readsTodayAll();

    final now = state.clock();
    final today = DateTime(now.year, now.month, now.day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          size: 48,
                          color: streak > 0 ? c.flame : c.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$streak',
                          style: TextStyle(
                            fontSize: 56,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: streak > 0 ? c.flame : c.muted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'day streak',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text('Best: $best',
                                style: TextStyle(fontSize: 12, color: c.blue)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _SavesBadge(tokens: state.tokens),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              streak == 0 && readsToday == 0
                  ? 'Decree today to start your streak.'
                  : readsToday == 0
                      ? 'Decree today to keep it going.'
                      : readsToday == 1
                          ? 'You have decreed once today.'
                          : 'You have decreed $readsToday times today.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 16),
            Divider(color: c.line),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StreakCalendarScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Last 7 days',
                            style: TextStyle(color: c.muted, fontSize: 13)),
                        const Spacer(),
                        Text('Calendar',
                            style: TextStyle(color: c.muted, fontSize: 13)),
                        Icon(Icons.chevron_right, size: 18, color: c.muted),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 6; i >= 0; i--)
                          _WeekDot(
                            day: DateTime(
                                today.year, today.month, today.day - i),
                            isToday: i == 0,
                            state: state,
                            letters: _weekdayLetters,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- helpers

/// One search hit: a decree plus the name of the space it lives in.
class _Hit {
  const _Hit(this.quote, this.source);

  final Quote quote;
  final String source;
}

/// A short one-line preview of a decree, shown under a space's name.
String _preview(String text) =>
    '"${text.replaceAll(RegExp(r'\s+'), ' ').trim()}"';

/// Splits [text] into spans, giving every case-insensitive match of [query]
/// a highlighted background.
List<InlineSpan> _highlightSpans(String text, String query, Color highlight) {
  if (query.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final q = query.toLowerCase();
  // Some characters change length when lower-cased; skip highlighting then.
  if (lower.length != text.length) return [TextSpan(text: text)];

  final spans = <InlineSpan>[];
  var start = 0;
  while (true) {
    final i = lower.indexOf(q, start);
    if (i < 0) {
      spans.add(TextSpan(text: text.substring(start)));
      break;
    }
    if (i > start) spans.add(TextSpan(text: text.substring(start, i)));
    spans.add(TextSpan(
      text: text.substring(i, i + q.length),
      style: TextStyle(backgroundColor: highlight),
    ));
    start = i + q.length;
  }
  return spans;
}

/// Streak saves: shield icons on top, a small count underneath. Kept
/// quieter than the streak itself.
class _SavesBadge extends StatelessWidget {
  const _SavesBadge({required this.tokens});

  final int tokens;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shown = tokens > 5 ? 5 : tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tokens <= 0)
              Icon(Icons.shield_outlined, size: 16, color: c.muted)
            else
              for (var i = 0; i < shown; i++)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                  child: Icon(Icons.shield, size: 16, color: c.blue),
                ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tokens == 1 ? '1 save' : '$tokens saves',
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Text(
        text,
        style: TextStyle(
          color: c.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _WeekDot extends StatelessWidget {
  const _WeekDot({
    required this.day,
    required this.isToday,
    required this.state,
    required this.letters,
  });

  final DateTime day;
  final bool isToday;
  final AppState state;
  final List<String> letters;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Text(
          letters[day.weekday - 1],
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        StreakDayDot(status: dayStatusFor(state, day), isToday: isToday),
      ],
    );
  }
}

class _SpaceRow extends StatelessWidget {
  const _SpaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.unread,
    required this.onTap,
    this.dueLabel,
    this.dueColor,
    this.personal = false,
    this.highlight = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int unread;
  final VoidCallback onTap;

  /// Optional due/next/last-read status shown above the unread pill.
  final String? dueLabel;
  final Color? dueColor;

  /// Personal gets a blue-tinted avatar; circles get a neutral one.
  final bool personal;

  /// Search text to highlight inside [title].
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: personal ? c.blue.withAlpha(46) : c.surface,
                border: personal ? null : Border.all(color: c.line),
              ),
              child: Icon(icon, color: personal ? c.blue : c.text),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: _highlightSpans(
                        title,
                        highlight,
                        c.flame.withAlpha(90),
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted),
                  ),
                ],
              ),
            ),
            if (dueLabel != null || unread > 0) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dueLabel != null)
                    Text(
                      dueLabel!,
                      style: TextStyle(fontSize: 11, color: dueColor ?? c.muted),
                    ),
                  if (unread > 0) ...[
                    if (dueLabel != null) const SizedBox(height: 4),
                    Container(
                      height: 24,
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.pill,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A decree that matched the search, with the match highlighted and the
/// space it belongs to underneath.
class _DecreeHitRow extends StatelessWidget {
  const _DecreeHitRow({required this.hit, required this.query});

  final _Hit hit;
  final String query;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuoteViewScreen(quoteId: hit.quote.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: quoteStyle(size: 16),
                children: _highlightSpans(
                  hit.quote.text,
                  query,
                  c.flame.withAlpha(90),
                ),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  hit.quote.isCircle
                      ? Icons.groups_outlined
                      : Icons.person_outline,
                  size: 14,
                  color: c.muted,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    hit.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
