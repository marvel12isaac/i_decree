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
      // Ghana has no daylight saving, so this is a safe fallback for now.
      tz.setLocalLocation(tz.UTC);
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
      settings: settings,          // was: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null) _onOpenQuote?.call(payload);
      },
    );

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
    try {
      await _plugin.cancelAll();
      for (final q in quotes) {
        if (!q.remindersOn) continue;
        final times = q.reminderMinutes();
        for (var i = 0; i < times.length; i++) {
          await _plugin.zonedSchedule(
            id: q.notifBase + i,
            title: 'Make a Decree!',
            body: _preview(q.text),
            scheduledDate: _nextOccurrence(times[i]),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: q.id,
          );
        }
      }

      final pending = await _plugin.pendingNotificationRequests();
      debugPrint('Reminders scheduled: ${pending.length}');
    } catch (e, st) {
      debugPrint('Scheduling reminders failed: $e\n$st');
    }
  }

  @override
  String? consumeLaunchQuoteId() {
    final id = _launchQuoteId;
    _launchQuoteId = null;
    return id;
  }

  tz.TZDateTime _nextOccurrence(int minutesFromMidnight) {
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

  String _preview(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 100 ? flat : '${flat.substring(0, 97)}...';
  }
}

ReminderService createPlatformReminderService() => MobileReminderService();
