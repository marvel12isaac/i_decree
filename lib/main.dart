import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/quote_view_screen.dart';
import 'services/reminder_service.dart';
import 'theme.dart';
import 'widgets/toast.dart';
// import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rahdhcyizsmqvxnridva.supabase.co',
    publishableKey: 'sb_publishable_ycXDAbe218WZlofKUleDzg_8n-QgCAG',
  );

  // final supabase = Supabase.instance.client;
  // final auth = AuthService(supabase);
  final reminders = createReminderService();
  // AppState.load also starts the account restore when signed in (backup
  // merge, channel memberships and content) and loads cached channels first.
  final state = await AppState.load(reminders);
  runApp(IDecreeApp(state: state));
}

class IDecreeApp extends StatefulWidget {
  const IDecreeApp({super.key, required this.state});

  final AppState state;

  @override
  State<IDecreeApp> createState() => _IDecreeAppState();
}

class _IDecreeAppState extends State<IDecreeApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// The decree opened from a notification that is still on screen. A tap can
  /// reach us twice (the launch details AND the tap callback, or the user
  /// tapping again while the app is still starting), so a second request for
  /// the same decree is ignored while it is already showing.
  String? _notificationQuoteId;
  final ThemeData _lightTheme = buildTheme();
  final ThemeData _darkTheme = buildDarkTheme();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startReminders();
  }

  Future<void> _startReminders() async {
    final reminders = widget.state.reminders;
    await reminders.init(_openQuote);

    // Open the decree the user tapped FIRST. Everything below (the
    // permission prompt and re-scheduling every reminder) can take many
    // seconds and must never sit in front of it.
    final launchId = reminders.consumeLaunchQuoteId();
    if (launchId != null) _openQuote(launchId);

    await reminders.requestPermission();
    // Re-schedule on every start, so reminders survive reboots and updates
    // even if the OS dropped them.
    await widget.state.syncReminders();

    // final auth = AuthService(Supabase.instance.client);
    // final user = await auth.signInWithGoogle();
    // debugPrint('Signed in as: ${user?.id} / ${user?.email}');
  }

  /// Opens a quote when the user taps its notification.
  void _openQuote(String quoteId) {
    if (widget.state.quoteById(quoteId) == null) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      // The first frame is not built yet: try again right after it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openQuote(quoteId));
      return;
    }
    // Already showing this decree from a notification: do nothing, so Back
    // goes straight to the list instead of through a second copy.
    if (_notificationQuoteId == quoteId) return;
    _notificationQuoteId = quoteId;
    navigator
        .push(
          MaterialPageRoute(builder: (_) => QuoteViewScreen(quoteId: quoteId)),
        )
        .whenComplete(() {
      if (_notificationQuoteId == quoteId) _notificationQuoteId = null;
    });
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
          home: const HomeScreen(),
        ),
      ),
    );
  }
}