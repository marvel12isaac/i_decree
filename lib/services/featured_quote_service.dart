import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// App-wide featured-quotes JSON hosted separately from any circle-owned file.
// This is intentionally distinct from circleJsonUrl in circle_service.dart.
const String featuredQuotesUrl =
    'https://raw.githubusercontent.com/marvel12isaac/i_decree_circles_decrees/refs/heads/main/featured_quotes.json';

/// One pre-loaded quote shown in the rotating card on My Decrees. Not tied to
/// a circle or to the user's own decrees, and not read-tracked — it's purely
/// something to see, mostly scripture, with its reference shown alongside.
class FeaturedQuote {
  FeaturedQuote({
    required this.id,
    required this.text,
    required this.reference,
  });

  final String id;
  final String text;

  /// Where the quote comes from, e.g. "Numbers 23:23 (NKJV)". Shown under
  /// the quote when not empty.
  final String reference;

  factory FeaturedQuote.fromJson(Map<String, dynamic> j) => FeaturedQuote(
        id: j['id'] as String,
        text: j['text'] as String,
        reference: (j['reference'] as String?) ?? '',
      );
}

/// Fetches the hosted featured-quotes JSON (a bare array of quote objects)
/// and caches the last successful response so the card still has something
/// to show offline.
class FeaturedQuoteService {
  FeaturedQuoteService({required this.url, required SharedPreferences prefs})
      : _prefs = prefs;

  final String url;
  final SharedPreferences _prefs;

  static const String _cacheKey = 'featured_quotes_cache_v1';
  static const Duration _timeout = Duration(seconds: 8);

  static List<FeaturedQuote> parse(String body) {
    final decoded = jsonDecode(body) as List<dynamic>;
    return decoded
        .map((q) => FeaturedQuote.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  /// Reads the last successfully fetched quotes from local cache, if any.
  List<FeaturedQuote>? loadCached() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return parse(raw);
    } catch (e) {
      debugPrint('Could not read cached featured decrees: $e');
      return null;
    }
  }

  /// Fetches the latest featured-quotes JSON from [url]. Returns null (and
  /// leaves the cache untouched) on any network or parsing failure.
  Future<List<FeaturedQuote>?> refresh() async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('Featured decrees fetch failed: HTTP ${response.statusCode}');
        return null;
      }
      final data = parse(response.body);
      await _prefs.setString(_cacheKey, response.body);
      return data;
    } catch (e) {
      debugPrint('Featured decrees fetch failed: $e');
      return null;
    }
  }
}
