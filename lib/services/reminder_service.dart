import 'reminder_service_base.dart';
import 'reminder_service_stub.dart'
    if (dart.library.io) 'reminder_service_mobile.dart';

export 'reminder_service_base.dart';
export 'reminder_service_stub.dart' show StubReminderService;

/// Returns the right reminder service for the current platform:
/// on-device notifications where dart:io exists (Android), a no-op on web.
ReminderService createReminderService() => createPlatformReminderService();
