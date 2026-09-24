import '../models.dart';

/// Platform-neutral reminder interface.
///
/// - Android (and other non-web platforms): on-device scheduled notifications
///   (reminder_service_mobile.dart).
/// - Web: no-op for now (reminder_service_stub.dart). Web reminders need push
///   from a server, which arrives in Stage 3.
abstract class ReminderService {
  /// False on platforms where reminders can't be scheduled yet (web, Stage 1).
  bool get supported;

  /// Call once at startup. [onOpenQuote] is called with a quote id when the
  /// user taps a notification while the app is running.
  Future<void> init(void Function(String quoteId) onOpenQuote);

  /// Ask the OS for notification permission. Returns true if granted (or if
  /// the platform doesn't need a permission).
  Future<bool> requestPermission();

  /// Make the scheduled notifications match [quotes] exactly.
  Future<void> syncAll(List<Quote> quotes);

  /// If the app was cold-started by tapping a notification, returns that
  /// quote's id once, then null.
  String? consumeLaunchQuoteId();
}
