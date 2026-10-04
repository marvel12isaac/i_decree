// reminder service mobile.dart
// VERIFY: every call into flutter_local_notifications, timezone and
// flutter_timezone is isolated in this file. The code targets
// flutter_local_notifications 22.x. If you upgrade the package, check its
// changelog: parameters of initialize()/zonedSchedule() have changed between
// major versions.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import 'reminder_service_base.dart';

class MobileReminderService implements ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  void Function(String quoteId)? _onOpenQuote;
  String? _launchQuoteId;

  // Cached in init(). On Android 12+ with SCHEDULE_EXACT_ALARM revoked,
  // exactAllowWhileIdle THROWS rather than failing silently — so we must
  // know before scheduling, not catch it after.
  bool _exactAlarmsAllowed = false;

  /// True when the IANA timezone lookup failed and we fell back to using
  /// the device's raw UTC offset for scheduling.
  bool _tzFallback = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'quote_reminders',
      'Quote reminders',
      channelDescription: 'Reminders to read your Decrees',
      importance: Importance.high,
      priority: Priority.high,
      // Must be a flat single-colour drawable — NOT a mipmap launcher icon.
      // The broadcast receiver resolves this outside the app process; a mipmap
      // icon returns a null resource ID there and crashes with NullPointerException.
      icon: 'ic_stat_idecree',
    ),
  );

  @override
  bool get supported => true;

  @override
  Future<void> init(void Function(String quoteId) onOpenQuote) async {
    _onOpenQuote = onOpenQuote;

    tzdata.initializeTimeZones();
    try {
      // Older flutter_timezone versions return a String; newer ones return an
      // object with an `identifier`. Handle both. (VERIFY against the version
      // you install.)
      final dynamic info = await FlutterTimezone.getLocalTimezone();
      final String name = info is String ? info : info.identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // IANA lookup failed (e.g. device reports an unknown zone name).
      // Fall back to the device's own UTC offset, which is always correct
      // for the user's current location. We do NOT set tz.local to UTC —
      // that would schedule at the wrong wall-clock time for anyone whose
      // device offset isn't zero.
      _tzFallback = true;
      tz.setLocalLocation(tz.UTC);
      debugPrint('Timezone lookup failed; using device UTC offset.');
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_idecree'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null) _onOpenQuote?.call(payload);
      },
    );

    // Capability check: exact alarms may be revoked by the user (Android 12+)
    // or unavailable on some OEMs. If the check itself throws, assume NO.
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      _exactAlarmsAllowed = await android?.canScheduleExactNotifications() ??
          false;
    } catch (e) {
      debugPrint('Exact-alarm capability check failed: $e');
      _exactAlarmsAllowed = false;
    }
    debugPrint('Exact alarms allowed: $_exactAlarmsAllowed');

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch != null && launch.didNotificationLaunchApp) {
      _launchQuoteId = launch.notificationResponse?.payload;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? true;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> syncAll(List<Quote> quotes) async {
    // Cancel outside the try: if a later schedule throws we must not end up
    // in a state where cancel succeeded but we treated the whole run as failed.
    await _plugin.cancelAll();

    final mode = _exactAlarmsAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    var scheduled = 0;
    var failed = 0;

    for (final q in quotes) {
      if (!q.remindersOn) continue;
      final times = q.reminderMinutes();
      for (var i = 0; i < times.length; i++) {
        try {
          await _plugin.zonedSchedule(
            id: q.notifBase + i,
            title: _title(q.text),            
            body: _preview(q.text),
            scheduledDate: _nextOccurrence(times[i]),
            notificationDetails: _details,
            androidScheduleMode: mode,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: q.id,
          );
          scheduled++;
        } catch (e) {
          // Per-notification isolation: one bad quote must not wipe out the
          // rest of the user's reminders.
          failed++;
          debugPrint('Schedule failed for quote ${q.id} slot $i: $e');
        }
      }
    }

    debugPrint('Reminders scheduled: $scheduled, failed: $failed '
        '(mode: ${_exactAlarmsAllowed ? "exact" : "inexact"})');
  }

  @override
  String? consumeLaunchQuoteId() {
    final id = _launchQuoteId;
    _launchQuoteId = null;
    return id;
  }

  tz.TZDateTime _nextOccurrence(int minutesFromMidnight) {
    if (_tzFallback) {
      // Compute the wall-clock time using the device's local clock and
      // offset, then convert to an absolute instant. tz.local is UTC here,
      // so building from milliseconds-since-epoch gives the correct instant.
      final now = DateTime.now();
      var scheduled = DateTime(
        now.year,
        now.month,
        now.day,
        minutesFromMidnight ~/ 60,
        minutesFromMidnight % 60,
      );
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      return tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC,
        scheduled.toUtc().millisecondsSinceEpoch,
      );
    }

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minutesFromMidnight ~/ 60,
      minutesFromMidnight % 60,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Notification title = the bold "title" part of the decree, matching the
  /// QuoteTitleBody split in the UI: everything before the first line break.
  /// No line break means the whole text is the title.
  String _title(String text) {
    final i = text.indexOf('\n');
    final t = (i < 0 ? text : text.substring(0, i)).trim();
    if (t.length <= 60) return t;
    return '${t.substring(0, 57)}...';
  }

  /// Notification body = the normal-weight body part (everything after the
  /// first line break). Falls back to the full text when there is no split.
  String _preview(String text) {
    final i = text.indexOf('\n');
    var body = i < 0 ? text : text.substring(i + 1).trim();
    if (body.isEmpty) body = text; // title-only decree: body repeats title
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 100 ? flat : '${flat.substring(0, 97)}...';
  }
}

ReminderService createPlatformReminderService() => MobileReminderService();