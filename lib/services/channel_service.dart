// channel_service.dart
// Supabase queries for channel discovery: search by name, lookup by join
// code, and fetching a channel's decrees for preview.
//
// Notes:
// - Reads are public (RLS "read" policies), so these work signed-out —
//   matching the browse-without-join model.
// - This service never writes. Joining/creating live in the join flow
//   (step 5) and channel editor (step 6).

import 'package:supabase_flutter/supabase_flutter.dart';

/// A channel as search results and preview show it.
class ChannelSummary {
  ChannelSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.decreesCount,
  });

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final int decreesCount;
}

/// A preview decree: the fields the read-only list screen needs.
class ChannelDecreePreview {
  ChannelDecreePreview({
    required this.id,
    required this.text,
    required this.targetPerDay,
  });

  final String id;
  final String text;
  final int targetPerDay;
}


/// A joined channel with its full decree list — the shape AppState's
/// feed needs.
class JoinedChannelData {
  JoinedChannelData({
    required this.id,
    required this.name,
    required this.description,
    this.quotes = const [],
  });

  factory JoinedChannelData.fromJson(Map<String, dynamic> j) =>
      JoinedChannelData(
        id: j['id'] as String,
        name: j['name'] as String,
        description: (j['description'] as String?) ?? '',
      );

  final String id;
  final String name;
  final String description;
  final List<JoinedQuoteData> quotes;
}

class JoinedQuoteData {
  JoinedQuoteData({
    required this.id,
    required this.text,
    required this.targetPerDay,
    required this.windowStartMin,
    required this.windowEndMin,
    required this.position,
  });

  final String id;
  final String text;
  final int targetPerDay;
  final int windowStartMin;
  final int windowEndMin;
  final int position;
}

class ChannelService {
  ChannelService(this._client);

  final SupabaseClient _client;

  /// Is this string shaped like a join code? (6 chars, letters/digits.)
  /// Codes are uppercase; we accept lowercase input and normalize.
  static bool looksLikeCode(String q) {
    final t = q.trim();
    return t.length == 6 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(t);
  }

  /// Search channels by name (public, searchable ones). Private channels
  /// are only reachable by code.
  Future<List<ChannelSummary>> searchByName(String query) async {
    final rows = await _client
        .from('channels')
        .select('id, name, description, join_code, '
            'channel_member_counts(member_count), channel_quotes(count)')
        .isFilter('join_code', null)
        .ilike('name', '%${query.trim()}%')
        .order('name')
        .limit(20);
    return rows.map(_summaryFrom).toList();
  }

  /// Exact lookup by join code. Returns null when no channel matches.
  /// Private channels are found ONLY through this path, via a server
  /// function — RLS deliberately hides private channels from direct
  /// queries, but possessing the code grants visibility.
  Future<ChannelDetail?> findByCode(String code) async {
    final res = await _client.rpc('channel_by_code',
        params: {'p_code': code.trim().toUpperCase()});
    if (res == null) return null;
    final r = res as Map<String, dynamic>;
    final decrees = (r['decrees'] as List)
        .map((q) => ChannelDecreePreview(
              id: q['id'] as String,
              text: q['text'] as String,
              targetPerDay: (q['target_per_day'] as int?) ?? 1,
            ))
        .toList();
    return ChannelDetail(
      summary: ChannelSummary(
        id: r['id'] as String,
        name: r['name'] as String,
        description: (r['description'] as String?) ?? '',
        memberCount: (r['member_count'] as int?) ?? 0,
        decreesCount: decrees.length,
      ),
      decrees: decrees,
    );
  }

  /// The decrees of one channel, for the preview screen.
  Future<List<ChannelDecreePreview>> fetchDecrees(String channelId) async {
    final rows = await _client
        .from('channel_quotes')
        .select('id, text, target_per_day')
        .eq('channel_id', channelId)
        .order('position')
        .limit(33);
    return rows
        .map((r) => ChannelDecreePreview(
              id: r['id'] as String,
              text: r['text'] as String,
              targetPerDay: (r['target_per_day'] as int?) ?? 1,
            ))
        .toList();
  }

    // ------------------------------------------------------------- joining

  /// Joins a private channel by its 6-character code. Requires sign-in.
  /// Returns the joined channel's summary data.
  Future<JoinedChannelData> joinByCode(String code) async {
    final res = await _client.rpc('join_by_code',
        params: {'p_code': code.trim().toUpperCase()});
    return JoinedChannelData.fromJson(res as Map<String, dynamic>);
  }

  /// Joins a public channel from the preview screen. Requires sign-in.
  Future<void> join(String channelId) async {
    await _client.rpc('join_channel', params: {'p_channel': channelId});
  }

  /// Leaves a channel (owners are refused server-side).
  Future<void> leave(String channelId) async {
    await _client.rpc('leave_channel', params: {'p_channel': channelId});
  }

  /// Full data for every joined channel: name + decrees. Used by AppState
  /// to build the feed.
  Future<List<JoinedChannelData>> fetchJoined(List<String> channelIds) async {
    if (channelIds.isEmpty) return [];
    final rows = await _client
        .from('channels')
        .select('id, name, description, channel_quotes(id, text, '
            'target_per_day, window_start_min, window_end_min, position)')
        .inFilter('id', channelIds)
        .order('name');
    return rows.map((r) {
      final quotes = (r['channel_quotes'] as List)
          .map((q) => JoinedQuoteData(
                id: q['id'] as String,
                text: q['text'] as String,
                targetPerDay: (q['target_per_day'] as int?) ?? 1,
                windowStartMin: (q['window_start_min'] as int?) ?? 480,
                windowEndMin: (q['window_end_min'] as int?) ?? 1200,
                position: (q['position'] as int?) ?? 0,
              ))
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      return JoinedChannelData(
        id: r['id'] as String,
        name: r['name'] as String,
        description: (r['description'] as String?) ?? '',
        quotes: quotes,
      );
    }).toList();
  }

  ChannelSummary _summaryFrom(dynamic row) {
    final r = row as Map<String, dynamic>;
    var memberCount = 0;
    final counts = r['channel_member_counts'] as List?;
    if (counts != null && counts.isNotEmpty) {
      memberCount = (counts.first['member_count'] as int?) ?? 0;
    }
    var decreesCount = 0;
    final decrees = r['channel_quotes'] as List?;
    if (decrees != null && decrees.isNotEmpty) {
      decreesCount = (decrees.first['count'] as int?) ?? 0;
    }
    return ChannelSummary(
      id: r['id'] as String,
      name: r['name'] as String,
      description: (r['description'] as String?) ?? '',
      memberCount: memberCount,
      decreesCount: decreesCount,
    );
  }
  
}

/// A channel plus its decrees, used by the code-match path so the preview
/// can render without a second query.
class ChannelDetail {
  ChannelDetail({required this.summary, required this.decrees});

  final ChannelSummary summary;
  final List<ChannelDecreePreview> decrees;
}