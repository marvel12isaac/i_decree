import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/quote_view_screen.dart';
import 'services/reminder_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rahdhcyizsmqvxnridva.supabase.co',
    publishableKey: 'sb_publishable_ycXDAbe218WZlofKUleDzg_8n-QgCAG',
  );

  final reminders = createReminderService();
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
    await reminders.requestPermission();
    // Re-schedule on every start, so reminders survive reboots and updates
    // even if the OS dropped them.
    await widget.state.syncReminders();
    final launchId = reminders.consumeLaunchQuoteId();
    if (launchId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openQuote(launchId));
    }
  }

  /// Opens a quote when the user taps its notification.
  void _openQuote(String quoteId) {
    if (widget.state.quoteById(quoteId) == null) return;
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => QuoteViewScreen(quoteId: quoteId)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      // A new day may have started while the app was in the background.
      widget.state.processMissedDays();
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
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: widget.state.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}