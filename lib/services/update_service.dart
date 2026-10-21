// lib/services/update_service.dart
// Tells existing users when a newer iDecree is available.
//
// How it works: one row in the Supabase table `app_versions` (see
// supabase_app_versions.sql) holds the latest version, the minimum version
// still allowed, release notes and the download link (the GitHub release).
// The app reads it at most once every 24 hours and compares it with the
// installed version.
//
// VERIFY: this needs two packages in pubspec.yaml. Add them with
//   flutter pub add package_info_plus url_launcher
// and check their current docs: calls used here are
//   PackageInfo.fromPlatform().version
//   launchUrl(Uri, mode: LaunchMode.externalApplication)
//
// Only the version NAME is compared (the part before the "+" in pubspec's
// `version: 0.1.0+1`). Bumping only the build number does not announce an
// update, so bump the name for every release you want people to see.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.installed,
    required this.latest,
    required this.minimum,
    required this.url,
    this.notes,
  });

  final String installed;
  final String latest;
  final String minimum;
  final String url;
  final String? notes;

  /// A newer version than the installed one exists.
  bool get available => UpdateService.compareVersions(installed, latest) < 0;

  /// The installed version is older than the minimum still supported.
  bool get isMandatory => UpdateService.compareVersions(installed, minimum) < 0;
}

class UpdateService {
  UpdateService._();

  static const String _cacheKey = 'update_cache_v1';
  static const String _checkedAtKey = 'update_checked_at_v1';
  static const String _dismissedKey = 'update_dismissed_version_v1';
  static const Duration _every = Duration(hours: 24);

  /// The update the Home banner should show right now, or null. A mandatory
  /// update always shows; an ordinary one shows until it is dismissed (and
  /// again when a still newer version is published).
  static final ValueNotifier<UpdateInfo?> pending =
      ValueNotifier<UpdateInfo?>(null);

  /// Checks for an update. Normally at most once per 24 hours (otherwise it
  /// answers from the saved copy). [force] always asks the server and
  /// returns null if it could not be reached.
  static Future<UpdateInfo?> check({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final installed = (await PackageInfo.fromPlatform()).version;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      Map<String, dynamic>? data;
      final cachedRaw = prefs.getString(_cacheKey);
      if (cachedRaw != null) {
        data = Map<String, dynamic>.from(jsonDecode(cachedRaw) as Map);
      }
      final last = prefs.getInt(_checkedAtKey);
      final fresh = !force &&
          data != null &&
          last != null &&
          nowMs - last < _every.inMilliseconds;

      var fetched = false;
      if (!fresh) {
        try {
          final row = await Supabase.instance.client
              .from('app_versions')
              .select('latest_version, min_version, notes, url')
              .limit(1)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));
          if (row != null) {
            data = Map<String, dynamic>.from(row);
            await prefs.setString(_cacheKey, jsonEncode(data));
            await prefs.setInt(_checkedAtKey, nowMs);
            fetched = true;
          }
        } catch (e) {
          debugPrint('Update check failed: $e');
        }
      }
      // A manual check that could not reach the server says so, instead of
      // answering from an old saved copy.
      if (force && !fetched) return null;
      if (data == null) return null;

      final latest = data['latest_version'] as String?;
      final url = data['url'] as String?;
      if (latest == null || url == null) return null;
      final info = UpdateInfo(
        installed: installed,
        latest: latest,
        minimum: (data['min_version'] as String?) ?? '0.0.0',
        url: url,
        notes: data['notes'] as String?,
      );

      final dismissed = prefs.getString(_dismissedKey);
      final show =
          info.isMandatory || (info.available && dismissed != info.latest);
      pending.value = show ? info : null;
      return info;
    } catch (e) {
      debugPrint('Update check error: $e');
      return null;
    }
  }

  /// Hides the banner for this version. A newer version brings it back.
  static Future<void> dismiss(UpdateInfo info) async {
    pending.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, info.latest);
  }

  /// Opens the release page in the browser. Returns false if it could not.
  static Future<bool> open(UpdateInfo info) async {
    try {
      return await launchUrl(
        Uri.parse(info.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Could not open update link: $e');
      return false;
    }
  }

  /// Compares version names like "0.1.0" and "0.2.10". Anything after a "+"
  /// or "-" is ignored. Returns negative, zero or positive like compareTo.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      final core = v.split('+').first.split('-').first.trim();
      return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }
}