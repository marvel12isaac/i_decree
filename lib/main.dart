import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'fx.dart';
import 'screens/home_screen.dart';
import 'screens/quote_view_screen.dart';
import 'services/reminder_service.dart';
import 'theme.dart';
import 'widgets/toast.dart';

// ---------------------------------------------------------------------------
// Start-up timing. Every stage prints "[startup] <ms since main()> <stage>".
// Read them with:  adb logcat -s flutter      (or `flutter run --release`)
// Time before main() (the Android process and Flutter engine starting) is NOT
// included, so also note roughly how long the splash screen stays up.
// Remove these calls once the delay is understood.
// ---------------------------------------------------------------------------
final Stopwatch _startup = Stopwatch();

void _mark(String stage) =>
    debugPrint('[startup] ${_startup.elapsedMilliseconds} ms  $stage');

/// Holds notification taps that arrive before the app widget exists, then
/// hands them over once it does.
class NotificationOpener {
  void Function(String quoteId)? _handler;
  final List<String> _early = [];

  void open(String quoteId) {
    final handler = _handler;
    if (handler == null) {
      _early.add(quoteId);
    } else {
      handler(quoteId);
    }
  }

  void attach(void Function(String quoteId) handler) {
    _handler = handler;
    final waiting = List<String>.of(_early);
    _early.clear();
    for (final id in waiting) {
      handler(id);
    }
  }
}

Future<void> main() async {
  _startup.start();
  _mark('main() entered');
  WidgetsFlutterBinding.ensureInitialized();
  _mark('binding ready');

  final reminders = createReminderService();
  final opener = NotificationOpener();

  // Supabase and the notification plugin don't depend on each other, so
  // start them together. reminders.init is now quick: it only registers the
  // plugin and reads which notification (if any) launched the app.
  await Future.wait<void>([
    Supabase.initialize(
      url: 'https://rahdhcyizsmqvxnridva.supabase.co',
      publishableKey: 'sb_publishable_ycXDAbe218WZlofKUleDzg_8n-QgCAG',
    ).then((_) => _mark('Supabase.initialize done')),
    reminders.init(opener.open).then((_) => _mark('reminders.init done')),
  ]);

  Fx.load(await SharedPreferences.getInstance());
  _mark('effects setting loaded');

  // AppState.load also starts the account restore when signed in (backup
  // merge, channel memberships and content) and loads cached channels first.
  final state = await AppState.load(reminders);
  _mark('AppState.load done');

  // If a notification launched the app, open straight onto that decree, so
  // Home never flashes first. A decree we don't know yet falls back to Home.
  var launchId = reminders.consumeLaunchQuoteId();
  if (launchId != null && state.quoteById(launchId) == null) {
    _mark('launch decree $launchId not found locally: opening Home');
    launchId = null;
  }
  _mark('launch decree: ${launchId ?? "none"}');

  runApp(IDecreeApp(state: state, opener: opener, launchQuoteId: launchId));
  _mark('runApp called');
}

class IDecreeApp extends StatefulWidget {
  const IDecreeApp({
    super.key,
    required this.state,
    required this.opener,
    this.launchQuoteId,
  });

  final AppState state;
  final NotificationOpener opener;

  /// The decree whose notification launched the app, if any.
  final String? launchQuoteId;

  @override
  State<IDecreeApp> createState() => _IDecreeAppState();
}

class _IDecreeAppState extends State<IDecreeApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// The last notification tap we acted on. The same tap can reach us twice
  /// within a moment (the launch details AND the tap callback), so a repeat
  /// of the same decree inside this window is ignored.
  String? _lastTapId;
  DateTime? _lastTapAt;
  static const Duration _repeatTapWindow = Duration(seconds: 1);

  final ThemeData _lightTheme = buildTheme();
  final ThemeData _darkTheme = buildDarkTheme();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.opener.attach(_openQuote);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  /// Everything slow happens AFTER the first frame, so it can never sit in
  /// front of the decree the user tapped.
  Future<void> _afterFirstFrame() async {
    _mark('first frame drawn');
    final reminders = widget.state.reminders;
    await reminders.requestPermission();
    _mark('permission step done');
    // Give the decree screen a moment to settle before the platform is
    // busy re-scheduling reminders.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    // Re-schedule on every start, so reminders survive reboots and updates
    // even if the OS dropped them.
    await widget.state.syncReminders();
    _mark('reminders synced');
  }

  /// The routes the app starts with. Normally just Home. When a notification
  /// launched the app: Home underneath and the decree on top, with no
  /// transition, so the decree is the first thing drawn and Back goes to Home.
  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute<void>(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case '/decree':
        final id = widget.launchQuoteId;
        if (id == null) return null;
        return FxPageRoute<void>(
          builder: (_) => QuoteViewScreen(quoteId: id),
          settings: settings,
        );
    }
    return null;
  }

  /// Handles a notification tap: "take me to this decree".
  ///
  /// - If that decree's page is already open, anywhere in the stack, close
  ///   everything above it and show it (its state is kept).
  /// - Otherwise close everything above Home (open editors, lists, dialogs;
  ///   any unsaved edit is discarded) and show a fresh decree page.
  ///
  /// Either way there is never a second page for the same decree.
  void _openQuote(String quoteId) {
    if (widget.state.quoteById(quoteId) == null) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      // The first frame is not built yet: try again right after it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openQuote(quoteId));
      return;
    }

    final now = DateTime.now();
    final lastAt = _lastTapAt;
    if (_lastTapId == quoteId &&
        lastAt != null &&
        now.difference(lastAt) < _repeatTapWindow) {
      return; // the same tap, delivered twice
    }
    _lastTapId = quoteId;
    _lastTapAt = now;

    final existing = OpenDecrees.routeFor(quoteId);
    if (existing != null) {
      navigator.popUntil((route) => identical(route, existing));
      return;
    }
    navigator.pushAndRemoveUntil(
      FxPageRoute<void>(builder: (_) => QuoteViewScreen(quoteId: quoteId)),
      (route) => route.isFirst,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      // A new day may have started while the app was in the background.
      widget.state.processMissedDays();
      // Pull in channel changes made elsewhere (at most every few minutes).
      unawaited(widget.state.refreshOnResume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) => MaterialApp(
          title: 'iDecree',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: rootMessengerKey,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: widget.state.themeMode,
          initialRoute: widget.launchQuoteId == null ? '/' : '/decree',
          onGenerateRoute: _onGenerateRoute,
        ),
      ),
    );
  }
}