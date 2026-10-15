import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import '../widgets/due_time.dart';
import '../widgets/read_crowns.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/legacy_circles_prompt.dart';
import 'channel_editor_screen.dart';
import 'circle_quote_list_screen.dart';
import 'quote_editor_screen.dart';
import 'quote_list_screen.dart';
import 'quote_view_screen.dart';
import 'settings_screen.dart';
import 'streak_calendar_screen.dart';

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Height of the pinned search bar (field plus its padding).
const double _searchBarHeight = 64;

// My Decrees card row sizes (wireframe 1).
const double _cardHeight = 108;
const double _featuredCardWidth = 170;
const double _decreeCardWidth = 166;
const double _addCardWidth = 64;

/// How many Discover channels show at once, and how often the list moves on
/// to the next batch when there are more than that.
const int _discoverCount = 5;
const Duration _discoverRotateEvery = Duration(minutes: 2);

/// Home (wireframes 1 and 1d): centered logo with theme toggle, the compact
/// streak card, the search field, a horizontal My Decrees card row (Featured
/// first, then decrees, then a dashed add card), the Channels section sorted
/// chat-style (most imminent decree on top), and a Discover channels section
/// of public channels the user hasn't joined.
///
/// Discover channels sits right after My Decrees while the user has no
/// channels, and below Channels once they have at least one.
///
/// Searching swaps everything below the header for unified results
/// (wireframes 2a/2b/2c): local decree hits plus channels. Unjoined channels
/// get [Join]; joined channels get [Open]. A join code that matches exactly
/// one channel shows only that channel. Back from search clears the search
/// instead of exiting the app.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _clockTimer;
  Timer? _discoverTimer;

  // Channel search (Supabase). Debounced so typing doesn't spam the net.
  late final ChannelService _channelService =
      ChannelService(Supabase.instance.client);
  Timer? _channelDebounce;
  int _channelRequestId = 0; // guards against out-of-order responses
  List<ChannelSummary> _channelResults = [];
  ChannelDetail? _codeMatch;
  String? _codeMatchFor; // the (upper-cased) code _codeMatch answers
  bool _channelSearchLoading = false;

  // Discover channels: a shuffled pool of public channels, shown a batch at
  // a time. Joined channels are filtered out at build time.
  List<ChannelSummary> _discoverPool = [];
  int _discoverOffset = 0;

  // Channel ids with a join in flight, so their button can show progress.
  final Set<String> _joiningIds = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    // Rebuild every minute so due/next/last-decreed labels stay current
    // without the user having to navigate away and back.
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _discoverTimer = Timer.periodic(_discoverRotateEvery, (_) {
      if (!mounted) return;
      if (_discoverPool.isEmpty) {
        _loadDiscover(); // earlier load failed (e.g. offline): try again
      } else if (_discoverPool.length > _discoverCount) {
        setState(() => _discoverOffset += _discoverCount);
      }
    });
    _loadDiscover();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowLegacyCirclesPrompt(context);
      });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _discoverTimer?.cancel();
    _channelDebounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- discover

  Future<void> _loadDiscover() async {
    try {
      final pool = await _channelService.fetchPublicChannels();
      if (!mounted) return;
      pool.shuffle(Random());
      setState(() {
        _discoverPool = pool;
        _discoverOffset = 0;
      });
    } catch (e) {
      // Discover is a nicety: stay hidden if it can't load.
      debugPrint('Discover channels failed to load: $e');
    }
  }

  // ----------------------------------------------------------------- search

  void _onSearchChanged() {
    _channelDebounce?.cancel();
    final query = _search.text.trim();
    if (query.isEmpty) {
      _channelRequestId++; // drop any in-flight response
      setState(() {
        _channelResults = [];
        _codeMatch = null;
        _codeMatchFor = null;
        _channelSearchLoading = false;
      });
      return;
    }
    setState(() => _channelSearchLoading = true);
    _channelDebounce = Timer(const Duration(milliseconds: 400), () {
      _runChannelSearch(query);
    });
  }

  Future<void> _runChannelSearch(String query) async {
    final id = ++_channelRequestId;
    try {
      // A code-shaped query is tried as a code first. If no channel has that
      // code it falls through to a normal name search (six-letter words like
      // "wisdom" look like codes too).
      if (ChannelService.looksLikeCode(query)) {
        final match = await _channelService.findByCode(query);
        if (!mounted || id != _channelRequestId) return;
        if (match != null) {
          setState(() {
            _codeMatch = match;
            _codeMatchFor = query.toUpperCase();
            _channelResults = [];
            _channelSearchLoading = false;
          });
          return;
        }
      }
      final results = await _channelService.searchByName(query);
      if (!mounted || id != _channelRequestId) return;
      setState(() {
        _channelResults = results;
        _codeMatch = null;
        _codeMatchFor = null;
        _channelSearchLoading = false;
      });
    } catch (e) {
      debugPrint('Channel search failed: $e');
      if (!mounted || id != _channelRequestId) return;
      // A network failure must not break local search; just show nothing.
      setState(() {
        _channelResults = [];
        _codeMatch = null;
        _codeMatchFor = null;
        _channelSearchLoading = false;
      });
    }
  }

  // ------------------------------------------------------------------ join

  /// Join flow shared by search rows and Discover rows: sign in if needed,
  /// then join by code (private channels found by code) or publicly.
  Future<void> _joinChannel(ChannelSummary ch, {String? code}) async {
    if (_joiningIds.contains(ch.id)) return;
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!state.isSignedIn) {
      final ok = await showSignInSheet(context, state);
      if (!ok || !mounted) return;
    }

    setState(() => _joiningIds.add(ch.id));
    try {
      if (code != null) {
        await state.joinChannelByCode(code);
      } else {
        await state.joinPublicChannel(ch.id);
      }
    } catch (e) {
      debugPrint('Join failed for ${ch.id}: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not join. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _joiningIds.remove(ch.id));
    }
  }

  void _openPreview(
    BuildContext context,
    ChannelSummary ch, {
    ChannelDetail? detail,
    String? code,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CircleQuoteListScreen(
          circleId: ch.id,
          channelName: ch.name,
          memberCount: ch.memberCount,
          decreesCount: ch.decreesCount,
          joinCode: code ?? ch.joinCode,
          preloadedQuotes: detail?.decrees,
          isChannelPreview: true,
        ),
      ),
    );
  }

  void _openChannel(BuildContext context, String channelId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CircleQuoteListScreen(circleId: channelId),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _search.text.trim();

    return PopScope(
      canPop: query.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        // Back from search results = clear the search, stay on Home.
        if (!didPop) _search.clear();
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Column(
            children: [
              // The logo and theme switch always stay in view.
              _buildHeader(state, isDark, c),
              Expanded(
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    // The sliver list is the same in both modes, so the
                    // search field (and its focus) isn't rebuilt when
                    // typing hides the streak card.
                    SliverToBoxAdapter(
                      child: query.isEmpty
                          ? _buildStreakCard(context, state, c)
                          : const SizedBox.shrink(),
                    ),
                    // The search bar scrolls with the page, then sticks
                    // under the header once it reaches the top.
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedHeaderDelegate(
                        height: _searchBarHeight,
                        color: c.background,
                        lineColor: c.line,
                        child: _buildSearchField(c),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: query.isEmpty
                            ? _buildHome(context, state, c)
                            : _buildResults(context, state, c, query),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- header

  /// One row of the Home menu: icon + text. The selected theme gets a tinted
  /// background and teal, bold text instead of a check mark.
  PopupMenuItem<String> _menuItem(
    AppColors c,
    String value,
    IconData icon,
    String label, {
    bool selected = false,
  }) {
    final color = selected ? c.teal : null;
    return PopupMenuItem<String>(
      value: value,
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: selected ? c.teal.withValues(alpha: 0.14) : null,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? c.muted),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            child: PopupMenuButton<String>(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'light':
                    state.setThemeMode(ThemeMode.light);
                    break;
                  case 'dark':
                    state.setThemeMode(ThemeMode.dark);
                    break;
                  case 'system':
                    state.setThemeMode(ThemeMode.system);
                    break;
                  case 'settings':
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                _menuItem(c, 'light', Icons.light_mode_outlined, 'Light',
                    selected: state.themeMode == ThemeMode.light),
                _menuItem(c, 'dark', Icons.dark_mode_outlined, 'Dark',
                    selected: state.themeMode == ThemeMode.dark),
                _menuItem(c, 'system', Icons.brightness_auto_outlined, 'System',
                    selected: state.themeMode == ThemeMode.system),
                const PopupMenuDivider(),
                _menuItem(c, 'settings', Icons.settings_outlined, 'Settings'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ streak card

  /// Compact streak card (wireframe 1): the flame with "streak" under it,
  /// the big number with "Best" below it, saves on the right, the 7-day
  /// dots, and a "More" link. The dots and "More" open the streak calendar.
  Widget _buildStreakCard(BuildContext context, AppState state, AppColors c) {
    final streak = state.dailyStreak();
    final best = state.bestDaily > streak ? state.bestDaily : streak;
    final accent = streak > 0 ? c.flame : c.muted;

    final now = state.clock();
    final today = DateTime(now.year, now.month, now.day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: _CardShell(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
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
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_fire_department,
                                size: 50, color: accent),
                            Text('Best: $best',
                                style:
                                    TextStyle(fontSize: 11, color: c.blue)),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$streak',
                              style: TextStyle(
                                fontSize: 56,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
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
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StreakCalendarScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 6; i >= 0; i--)
                          _WeekDot(
                            day: DateTime(
                                today.year, today.month, today.day - i),
                            isToday: i == 0,
                            state: state,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('More',
                              style: TextStyle(color: c.muted, fontSize: 13)),
                          Icon(Icons.chevron_right, size: 18, color: c.muted),
                        ],
                      ),
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

  // ----------------------------------------------------------------- search

  Widget _buildSearchField(AppColors c) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c.line),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      child: Center(
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search decrees, channels, or code',
            hintStyle: TextStyle(color: c.muted),
            prefixIcon: Icon(Icons.search, color: c.muted),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: Icon(Icons.close, color: c.muted),
                    onPressed: _search.clear,
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
      ),
    );
  }

  // ------------------------------------------------------------- home body

  List<Widget> _buildHome(BuildContext context, AppState state, AppColors c) {
    final channels = _channelsSorted(state);
    final discover = _buildDiscover(context, state, c);

    return [
      if (!state.reminders.supported)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Reminders work in the Android app. Web reminders come later.',
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ),
      _SectionLabel(
        'My Decrees',
        showChevron: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuoteListScreen()),
        ),
      ),
      _buildDecreeCards(context, state, c),
      const SizedBox(height: 8),
      // No channels yet: Discover goes first so a new user can join one.
      if (channels.isEmpty) ...discover,
      _SectionLabel(
        'Channels',
        trailing: _NewChannelButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChannelEditorScreen()),
          ),
        ),
      ),
      if (channels.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Text('No channels yet', style: TextStyle(color: c.muted)),
        )
      else
        for (final circle in channels) ...[
          _channelRow(context, state, c, circle),
          const Divider(),
        ],
      if (channels.isNotEmpty) ...discover,
      // A signed-out device with no decrees and no channels (new install or
      // cleared data): offer the way back to an existing account.
      if (!state.isSignedIn && state.quotes.isEmpty && !state.hasJoinedChannels)
        _RestoreLink(
          onPressed: () {
            showSignInSheet(context, state, title: 'Sign in to restore.');
          },
        ),
      const SizedBox(height: 12),
    ];
  }

  /// Wireframe 1's horizontal card row: Featured first, then one card per
  /// personal decree, then the dashed add card.
  Widget _buildDecreeCards(BuildContext context, AppState state, AppColors c) {
    final cards = <Widget>[];

    // Featured card: rotating quote; tapping opens My Decrees.
    if (state.featuredQuotes.isNotEmpty) {
      cards.add(_FeaturedCard(
        state: state,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuoteListScreen()),
        ),
      ));
    }

    for (final quote in state.quotes) {
      final due = state.dueInfoFor(quote);
      cards.add(_DecreeCard(
        text: quote.text,
        dueLabel: dueLabelText(context, due),
        dueColor: dueLabelColor(due, c),
        done: state.readsTodayFor(quote.id),
        target: quote.targetPerDay,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QuoteViewScreen(quoteId: quote.id)),
        ),
      ));
    }

    cards.add(_AddCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const QuoteEditorScreen()),
      ),
    ));

    // Fixed height keeps the horizontal list valid inside Home's vertical
    // scroll view (the extra 4 is bottom padding).
    return SizedBox(
      height: _cardHeight + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }

  /// Discover channels: up to [_discoverCount] public channels the user
  /// hasn't joined, moving through the pool in batches. Empty when there is
  /// nothing to show (not loaded, offline, or everything already joined).
  List<Widget> _buildDiscover(
    BuildContext context,
    AppState state,
    AppColors c,
  ) {
    final available = [
      for (final ch in _discoverPool)
        if (!state.isMemberOf(ch.id)) ch,
    ];
    if (available.isEmpty) return const [];

    final shown = available.length <= _discoverCount
        ? available
        : [
            for (var i = 0; i < _discoverCount; i++)
              available[(_discoverOffset + i) % available.length],
          ];

    return [
      const _SectionLabel('Discover channels'),
      for (final ch in shown) ...[
        _ChannelResultRow(
          name: ch.name,
          memberCount: ch.memberCount,
          decreesCount: ch.decreesCount,
          joined: false,
          busy: _joiningIds.contains(ch.id),
          onTap: () => _openPreview(context, ch),
          onAction: () => _joinChannel(ch),
        ),
        const Divider(),
      ],
      const SizedBox(height: 8),
    ];
  }

  /// Channels sorted chat-style: the one with the most imminent decree on
  /// top — overdue first (longest-waiting slot first), then upcoming
  /// (soonest first), then recently decreed, then the rest.
  List<Circle> _channelsSorted(AppState state) => state.channelsByDue();

  /// One joined channel's Home row: avatar, name, first-decree preview, and
  /// the combined due/next/last-decreed status with unread badge on the
  /// right. No member count: once you're in, you care about the decrees.
  Widget _channelRow(
    BuildContext context,
    AppState state,
    AppColors c,
    Circle circle,
  ) {
    final due = state.spaceDueInfo(circle.quotes);
    return _ChannelRow(
      title: circle.name,
      subtitle: circle.quotes.isEmpty
          ? 'No decrees yet'
          : _quotePreview(circle.quotes.first.text),
      unread: state.unreadCountFor(circle.quotes),
      dueLabel: dueLabelText(context, due),
      dueColor: dueLabelColor(due, c),
      onTap: () => _openChannel(context, circle.id),
    );
  }

  // --------------------------------------------------------------- results

  List<Widget> _buildResults(
    BuildContext context,
    AppState state,
    AppColors c,
    String query,
  ) {
    // Wireframe 2b: a code that matches one channel shows only that channel.
    final match = _codeMatch;
    if (match != null && _codeMatchFor == query.toUpperCase()) {
      return [
        const _SectionLabel('Channels'),
        _searchChannelRow(
          context,
          state,
          match.summary,
          detail: match,
          code: query.toUpperCase(),
          highlight: query,
        ),
        const Divider(),
      ];
    }

    final q = query.toLowerCase();

    // --- Local results (instant) ---
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

    // Joined channels that match by name get [Open]. Counts come from the
    // server result when it has one; otherwise just the local decree count.
    final channelRows = <Widget>[
      for (final circle in state.circles)
        if (circle.name.toLowerCase().contains(q))
          _ChannelResultRow(
            name: circle.name,
            memberCount: _summaryFor(circle.id)?.memberCount,
            decreesCount:
                _summaryFor(circle.id)?.decreesCount ?? circle.quotes.length,
            joined: true,
            busy: false,
            highlight: query,
            onTap: () => _openChannel(context, circle.id),
            onAction: () => _openChannel(context, circle.id),
          ),
      // Channels not joined yet get [Join].
      for (final ch in _channelResults)
        if (!state.isMemberOf(ch.id))
          _searchChannelRow(context, state, ch, highlight: query),
    ];

    if (hits.isEmpty && channelRows.isEmpty && !_channelSearchLoading) {
      return [const _EmptyResults()];
    }

    return [
      if (hits.isNotEmpty) ...[
        const _SectionLabel('My Decrees'),
        for (final hit in hits) ...[
          _DecreeHitRow(hit: hit, query: query),
          const Divider(),
        ],
      ],
      if (channelRows.isNotEmpty) ...[
        const _SectionLabel('Channels'),
        for (final row in channelRows) ...[row, const Divider()],
      ],
      if (_channelSearchLoading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
  }

  ChannelSummary? _summaryFor(String channelId) {
    for (final ch in _channelResults) {
      if (ch.id == channelId) return ch;
    }
    return null;
  }

  /// A search row for a channel that came from the server: [Join] if the
  /// user hasn't joined it, [Open] if they have.
  Widget _searchChannelRow(
    BuildContext context,
    AppState state,
    ChannelSummary ch, {
    ChannelDetail? detail,
    String? code,
    String highlight = '',
  }) {
    final joined = state.isMemberOf(ch.id);
    return _ChannelResultRow(
      name: ch.name,
      memberCount: ch.memberCount,
      decreesCount: ch.decreesCount,
      joined: joined,
      busy: _joiningIds.contains(ch.id),
      highlight: highlight,
      onTap: joined
          ? () => _openChannel(context, ch.id)
          : () => _openPreview(context, ch, detail: detail, code: code),
      onAction: joined
          ? () => _openChannel(context, ch.id)
          : () => _joinChannel(ch, code: code),
    );
  }
}

// ---------------------------------------------------------------- helpers

/// "1 member" / "2 members" — 0 takes the plural. Plural is [one] + 's'
/// unless overridden.
String _plural(int n, String one, [String? many]) =>
    n == 1 ? '1 $one' : '$n ${many ?? '${one}s'}';

/// A short one-line preview of a decree, shown under a channel's name.
String _quotePreview(String text) =>
    '"${text.replaceAll(RegExp(r'\s+'), ' ').trim()}"';

/// Splits a decree at its first line break into a title (first line) and a
/// body (the rest), the same rule the decree lists use.
({String title, String body}) _splitTitleBody(String text) {
  final trimmed = text.trim();
  final i = trimmed.indexOf('\n');
  if (i < 0) return (title: trimmed, body: '');
  return (
    title: trimmed.substring(0, i).trim(),
    body: trimmed.substring(i + 1).replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

/// Width the crowns need next to a status label, so [ReadCrowns] (which
/// expands to fill its parent) can sit in a Row without unbounded width.
double _crownsWidth(int done, int target, {double size = 12}) {
  final total = target < 1 ? 1 : target;
  final hasExtra = done > total;
  final width = total * (size + 3) + (hasExtra ? 40 : 0);
  return width > 110 ? 110 : width;
}

/// One search hit: a decree plus the name of the space it lives in.
class _Hit {
  const _Hit(this.quote, this.source);

  final Quote quote;
  final String source;
}

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

/// A rounded, bordered card whose tap ripple is visible (the ink is painted
/// on the Material itself, not hidden behind a decorated Container).
class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    this.onTap,
    this.radius = 12,
    this.borderColor,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color? borderColor;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor ?? c.line),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Streak saves: one big shield with the number of saves left inside it,
/// like the due pills. Filled blue while saves remain, an outline at zero.
class _SavesBadge extends StatelessWidget {
  const _SavesBadge({required this.tokens});

  final int tokens;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final has = tokens > 0;
    return Semantics(
      label: tokens == 1 ? '1 streak save' : '$tokens streak saves',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  has ? Icons.shield : Icons.shield_outlined,
                  size: 36,
                  color: has ? c.blue : c.muted,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '$tokens',
                    style: TextStyle(
                      color: has ? Colors.white : c.muted,
                      fontSize: tokens > 9 ? 11 : 15,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text('Saves', style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// A section header: bold label, optional chevron and tap (whole row), and
/// an optional trailing widget.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
    this.text, {
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  final String text;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final label = Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, size: 20, color: c.text),
        ],
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: label,
    );
    if (onTap == null) return padded;
    return InkWell(onTap: onTap, child: padded);
  }
}

/// The solid "＋ New" pill next to the Channels header, styled like the Join
/// buttons.
class _NewChannelButton extends StatelessWidget {
  const _NewChannelButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New channel',
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18),
            SizedBox(width: 4),
            Text('New'),
          ],
        ),
      ),
    );
  }
}

/// Wireframe 1's teal-bordered Featured card, first in the My Decrees row.
/// Shows the shared featured quote from [AppState] (one index, one timer),
/// so it is always the same quote as the card on the My Decrees page.
/// Tapping opens My Decrees.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: state.featuredIndex,
      builder: (context, index, _) {
        final quote = state.featuredQuoteAt(index);
        if (quote == null) return const SizedBox.shrink();

        return _CardShell(
          width: _featuredCardWidth,
          height: _cardHeight,
          borderColor: c.teal,
          padding: const EdgeInsets.all(10),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: c.teal),
                  const SizedBox(width: 4),
                  Text(
                    'Featured',
                    style: TextStyle(
                      fontSize: 11,
                      color: c.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  quote.text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: quoteStyle(size: 12, color: c.text),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Already have an account? Sign in", shown on a fresh signed-out device.
class _RestoreLink extends StatelessWidget {
  const _RestoreLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: TextButton(
          onPressed: onPressed,
          child: Text.rich(
            TextSpan(
              style: TextStyle(color: c.muted, fontSize: 14),
              children: [
                const TextSpan(text: 'Already have an account? '),
                TextSpan(
                  text: 'Sign in',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pins the search bar under the header. Opaque so content scrolls beneath
/// it, with a hairline underneath once content is actually behind it.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.height,
    required this.color,
    required this.lineColor,
    required this.child,
  });

  final double height;
  final Color color;
  final Color lineColor;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: overlapsContent
            ? Border(bottom: BorderSide(color: lineColor))
            : null,
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) => true;
}

/// One personal decree card in the My Decrees row, laid out like the My
/// Decrees list: bold title (ellipsized), body (ellipsized), then the status
/// on the left and crowns on the right.
class _DecreeCard extends StatelessWidget {
  const _DecreeCard({
    required this.text,
    required this.dueLabel,
    required this.dueColor,
    required this.done,
    required this.target,
    required this.onTap,
  });

  final String text;

  /// Null when there's no status to show (e.g. reminders off, never decreed).
  final String? dueLabel;
  final Color? dueColor;
  final int done;
  final int target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final parts = _splitTitleBody(text);
    final hasBody = parts.body.isNotEmpty;

    return _CardShell(
      width: _decreeCardWidth,
      height: _cardHeight,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parts.title,
                  // With no body, let a long one-line decree use more room.
                  maxLines: hasBody ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: quoteStyle(size: 13, color: c.text)
                      .copyWith(fontWeight: FontWeight.w700, height: 1.25),
                ),
                if (hasBody)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      parts.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: quoteStyle(size: 11.5, color: c.muted)
                          .copyWith(height: 1.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  dueLabel ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: dueColor ?? c.muted),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: _crownsWidth(done, target),
                child: ReadCrowns(done: done, target: target, size: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dashed add card at the end of the My Decrees row.
class _AddCard extends StatelessWidget {
  const _AddCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      label: 'Add a decree',
      child: SizedBox(
        width: _addCardWidth,
        height: _cardHeight,
        child: CustomPaint(
          painter: _DashedRRectPainter(color: c.muted, radius: 12),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: onTap,
            child: Center(child: Icon(Icons.add, size: 28, color: c.muted)),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rectangle outline.
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.6);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = min(distance + 5, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

class _WeekDot extends StatelessWidget {
  const _WeekDot({
    required this.day,
    required this.isToday,
    required this.state,
  });

  final DateTime day;
  final bool isToday;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Text(
          _weekdayLetters[day.weekday - 1],
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        StreakDayDot(status: dayStatusFor(state, day), isToday: isToday),
      ],
    );
  }
}

/// The round channel avatar. Will hold the channel's icon or crest later.
class _ChannelAvatar extends StatelessWidget {
  const _ChannelAvatar();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface,
        border: Border.all(color: c.line),
      ),
      child: Icon(Icons.groups_outlined, color: c.text),
    );
  }
}

/// A joined channel's row on Home: avatar, name, decree preview, and the
/// due/next/last-decreed status with an unread badge on the right.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.title,
    required this.subtitle,
    required this.unread,
    required this.onTap,
    this.dueLabel,
    this.dueColor,
  });

  final String title;
  final String subtitle;
  final int unread;
  final VoidCallback onTap;

  /// Optional due/next/last-decreed status shown above the unread pill.
  final String? dueLabel;
  final Color? dueColor;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            const _ChannelAvatar(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                      style:
                          TextStyle(fontSize: 11, color: dueColor ?? c.muted),
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

/// A channel in search results or Discover: avatar, name, counts, and a
/// [Join] button (not joined) or [Open] button (joined).
class _ChannelResultRow extends StatelessWidget {
  const _ChannelResultRow({
    required this.name,
    required this.memberCount,
    required this.decreesCount,
    required this.joined,
    required this.busy,
    required this.onTap,
    required this.onAction,
    this.highlight = '',
  });

  final String name;

  /// Null when the member count isn't known (e.g. a joined private channel
  /// with no server result).
  final int? memberCount;
  final int decreesCount;
  final bool joined;
  final bool busy;
  final String highlight;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const compactPadding = EdgeInsets.symmetric(horizontal: 16);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            const _ChannelAvatar(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: _highlightSpans(
                        name,
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
                  _ChannelCounts(members: memberCount, decrees: decreesCount),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (joined)
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: compactPadding,
                ),
                child: const Text('Open'),
              )
            else
              FilledButton(
                onPressed: busy ? null : onAction,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: compactPadding,
                ),
                child: Text(busy ? 'Joining…' : 'Join'),
              ),
          ],
        ),
      ),
    );
  }
}

/// "people icon, members · N decrees" (members part omitted when unknown).
class _ChannelCounts extends StatelessWidget {
  const _ChannelCounts({required this.members, required this.decrees});

  final int? members;
  final int decrees;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextStyle(color: c.muted, fontSize: 13);
    final decreesText = _plural(decrees, 'decree');

    if (members == null) {
      return Text(decreesText, style: style);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.people_outline, size: 15, color: c.muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$members · $decreesText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Center(
        child: Text(
          'No matches — try a channel code like A1B2C3.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: c.muted),
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