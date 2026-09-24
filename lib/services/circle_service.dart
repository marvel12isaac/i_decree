import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// TODO: replace with your actual GitHub raw URL once you've pushed the circle JSON to a public repo, e.g. https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/circle.json
const String circleJsonUrl =
    'https://raw.githubusercontent.com/marvel12isaac/i_decree_circles_decrees/refs/heads/main/circle_decrees.json';

/// One quote as it appears in the hosted circle JSON.
class CircleQuoteData {
  CircleQuoteData({
    required this.id,
    required this.text,
    required this.targetPerDay,
    required this.windowStartMin,
    required this.windowEndMin,
  });

  final String id;
  final String text;
  final int targetPerDay;
  final int windowStartMin;
  final int windowEndMin;

  factory CircleQuoteData.fromJson(Map<String, dynamic> j) => CircleQuoteData(
        id: j['id'] as String,
        text: j['text'] as String,
        targetPerDay: (j['targetPerDay'] as int?) ?? 1,
        windowStartMin: (j['windowStartMin'] as int?) ?? 5 * 60,
        windowEndMin: (j['windowEndMin'] as int?) ?? 24 * 60,
      );
}

/// The hosted circle file: one circle, its display name, and its quotes.
class CircleData {
  CircleData({required this.id, required this.name, required this.quotes});

  final String id;
  final String name;
  final List<CircleQuoteData> quotes;

  factory CircleData.fromJson(Map<String, dynamic> j) => CircleData(
        id: j['id'] as String,
        name: j['name'] as String,
        quotes: (j['quotes'] as List<dynamic>? ?? [])
            .map((q) => CircleQuoteData.fromJson(q as Map<String, dynamic>))
            .toList(),
      );
}

/// Fetches the circle JSON and caches the last successful response so the
/// circles still show something when the device is offline.
///
/// The hosted file can be a single circle object (the old format) or an
/// array of circle objects.
class CircleService {
  CircleService({required this.url, required SharedPreferences prefs})
      : _prefs = prefs;

  final String url;
  final SharedPreferences _prefs;

  static const String _cacheKey = 'circle_cache_v1';
  static const Duration _timeout = Duration(seconds: 8);

  /// Turns the raw JSON text into circles. Throws if any circle is malformed,
  /// so a half-broken file never replaces a good cache.
  static List<CircleData> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded
          .map((c) => CircleData.fromJson(c as Map<String, dynamic>))
          .toList();
    }
    return [CircleData.fromJson(decoded as Map<String, dynamic>)];
  }

  /// Reads the last successfully fetched circles from local cache, if any.
  List<CircleData>? loadCached() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return parse(raw);
    } catch (e) {
      debugPrint('Could not read cached circles: $e');
      return null;
    }
  }

  /// Fetches the latest circle JSON from [url]. Returns null (and leaves the
  /// cache untouched) on any network or parsing failure.
  Future<List<CircleData>?> refresh() async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('Circle fetch failed: HTTP ${response.statusCode}');
        return null;
      }
      final data = parse(response.body);
      await _prefs.setString(_cacheKey, response.body);
      return data;
    } catch (e) {
      debugPrint('Circle fetch failed: $e');
      return null;
    }
  }
}