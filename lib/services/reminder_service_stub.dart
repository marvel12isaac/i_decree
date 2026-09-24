import '../models.dart';
import 'reminder_service_base.dart';

/// Used on web (Stage 1) and in tests. Does nothing.
class StubReminderService implements ReminderService {
  @override
  bool get supported => false;

  @override
  Future<void> init(void Function(String quoteId) onOpenQuote) async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> syncAll(List<Quote> quotes) async {}

  @override
  String? consumeLaunchQuoteId() => null;
}

ReminderService createPlatformReminderService() => StubReminderService();
