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
  /// Private channels are found ONLY through this path.
  Future<ChannelSummary?> findByCode(String code) async {
    final rows = await _client
        .from('channels')
        .select('id, name, description, join_code, '
            'channel_member_counts(member_count), channel_quotes(count)')
        .eq('join_code', code.trim().toUpperCase())
        .limit(1);
    if (rows.isEmpty) return null;
    return _summaryFrom(rows.first);
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