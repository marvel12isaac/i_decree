// channel_service.dart
// Supabase queries for channel discovery, joining, creating, managing,
// and reading.
//
// Notes:
// - Public channel reads work signed-out (browse-without-join model).
// - Private channels are reachable ONLY by code, via server functions
//   (RLS hides them from direct queries; possessing the code grants access).
// - This service never touches local state — AppState owns that.

import 'package:supabase_flutter/supabase_flutter.dart';

/// A channel as search results and preview show it.
class ChannelSummary {
  ChannelSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.decreesCount,
    this.joinCode,
  });

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final int decreesCount;

  /// Set only when the caller already knows the code (code-match path).
  final String? joinCode;
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

/// A channel plus its decrees, used by the code-match path so the preview
/// can render without a second query.
class ChannelDetail {
  ChannelDetail({required this.summary, required this.decrees});

  final ChannelSummary summary;
  final List<ChannelDecreePreview> decrees;
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

/// The result of creating a channel.
class CreatedChannel {
  CreatedChannel({required this.id, required this.name, this.joinCode});

  final String id;
  final String name;

  /// Null for public channels.
  final String? joinCode;
}

/// A decree being drafted in the editor.
class EditorDecree {
  EditorDecree({
    required this.text,
    this.targetPerDay = 1,
    this.windowStartMin = 8 * 60,
    this.windowEndMin = 20 * 60,
  });

  String text;
  int targetPerDay;
  int windowStartMin;
  int windowEndMin;
}

/// A stored channel decree with its server id — what the edit-decrees
/// screen loads and saves.
class StoredDecree {
  StoredDecree({
    required this.id,
    required this.text,
    required this.targetPerDay,
    required this.windowStartMin,
    required this.windowEndMin,
  });

  final String id;
  String text;
  int targetPerDay;
  int windowStartMin;
  int windowEndMin;
}

/// One channel member, as the settings screen shows them.
class ChannelMemberInfo {
  ChannelMemberInfo({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role; // owner | admin | member
}

/// Per-decree participation stats (creator view).
class DecreeStat {
  DecreeStat({
    required this.quoteId,
    required this.text,
    required this.participants,
    required this.fullCompletions,
    required this.partial,
  });

  final String quoteId;
  final String text;
  final int participants;
  final int fullCompletions;
  final int partial;
}

class ChannelService {
  ChannelService(this._client);

  final SupabaseClient _client;

  /// Is this string shaped like a join code? (6 chars, letters/digits.)
  static bool looksLikeCode(String q) {
    final t = q.trim();
    return t.length == 6 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(t);
  }

  // ------------------------------------------------------------- discovery

  /// Search channels by name (public, searchable ones). Private channels
  /// are only reachable by code. Filtered for public BOTH server-side and
  /// client-side — the client-side check is the guarantee.
  Future<List<ChannelSummary>> searchByName(String query) async {
    final rows = await _client
        .from('channels')
        .select('id, name, description, join_code, '
            'channel_member_counts(member_count), channel_quotes(count)')
        .isFilter('join_code', null)
        .ilike('name', '%${query.trim()}%')
        .order('name')
        .limit(20);
    return rows
        .where((r) => r['join_code'] == null) // defense in depth
        .map(_summaryFrom)
        .toList();
  }

  /// Public channels for Home's "Discover channels" section: a pool the
  /// caller shuffles, filters against joined channels, and shows a few at a
  /// time. Public means join_code is null, checked server-side and again
  /// client-side. Channels with no decrees are skipped (nothing to preview).
  Future<List<ChannelSummary>> fetchPublicChannels({int limit = 50}) async {
    final rows = await _client
        .from('channels')
        .select('id, name, description, join_code, '
            'channel_member_counts(member_count), channel_quotes(count)')
        .isFilter('join_code', null)
        .order('name')
        .limit(limit);
    return rows
        .where((r) => r['join_code'] == null) // defense in depth
        .map(_summaryFrom)
        .where((s) => s.decreesCount > 0)
        .toList();
  }

  /// Exact lookup by join code. Private channels are found ONLY through
  /// this path — possessing the code grants visibility.
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

  /// The decrees of one channel (preview shape).
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

  /// Full decrees of one channel (edit shape) — managers only, enforced
  /// by RLS (read is public; but only managers get here in the UI).
  Future<List<StoredDecree>> fetchDecreesForEdit(String channelId) async {
    final rows = await _client
        .from('channel_quotes')
        .select('id, text, target_per_day, window_start_min, window_end_min')
        .eq('channel_id', channelId)
        .order('position')
        .limit(33);
    return rows
        .map((r) => StoredDecree(
              id: r['id'] as String,
              text: r['text'] as String,
              targetPerDay: (r['target_per_day'] as int?) ?? 1,
              windowStartMin: (r['window_start_min'] as int?) ?? 480,
              windowEndMin: (r['window_end_min'] as int?) ?? 1200,
            ))
        .toList();
  }

  /// Live member/decree counts for one channel.
  Future<ChannelSummary?> fetchSummary(String channelId) async {
    final rows = await _client
        .from('channels')
        .select('id, name, description, join_code, '
            'channel_member_counts(member_count), channel_quotes(count)')
        .eq('id', channelId)
        .limit(1);
    if (rows.isEmpty) return null;
    return _summaryFrom(rows.first);
  }

  // ------------------------------------------------------------- joining

  /// Joins a private channel by its 6-character code. Requires sign-in.
  Future<JoinedChannelData> joinByCode(String code) async {
    final res = await _client.rpc('join_by_code',
        params: {'p_code': code.trim().toUpperCase()});
    return JoinedChannelData.fromJson(res as Map<String, dynamic>);
  }

  /// Joins a public channel. Requires sign-in.
  Future<void> join(String channelId) async {
    await _client.rpc('join_channel', params: {'p_channel': channelId});
  }

  /// Leaves a channel (owners are refused server-side).
  Future<void> leave(String channelId) async {
    await _client.rpc('leave_channel', params: {'p_channel': channelId});
  }

  /// The channel IDs the signed-in user belongs to.
  Future<List<String>> fetchMyMembershipIds() async {
    final rows = await _client
        .from('channel_memberships')
        .select('channel_id')
        .eq('user_id', _client.auth.currentUser!.id);
    return rows.map((r) => r['channel_id'] as String).toList();
  }

  /// The signed-in user's role in a channel: owner/admin/member, or
  /// 'none' when not a member.
  Future<String> fetchMyRole(String channelId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 'none';
    final rows = await _client
        .from('channel_memberships')
        .select('role')
        .eq('channel_id', channelId)
        .eq('user_id', uid)
        .limit(1);
    if (rows.isEmpty) return 'none';
    return (rows.first['role'] as String?) ?? 'none';
  }

  /// Full data for every joined channel: name + decrees.
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

  // ------------------------------------------------------------ creating

  /// Creates a channel. Creator becomes owner-member server-side.
  Future<CreatedChannel> create({
    required String name,
    required String description,
    required bool isPublic,
  }) async {
    final res = await _client.rpc('create_channel', params: {
      'p_name': name.trim(),
      'p_description': description.trim(),
      'p_public': isPublic,
    });
    final r = res as Map<String, dynamic>;
    return CreatedChannel(
      id: r['id'] as String,
      name: r['name'] as String,
      joinCode: r['join_code'] as String?,
    );
  }

  /// Replaces all of a channel's decrees with the given list.
  Future<void> replaceDecrees(
      String channelId, List<EditorDecree> decrees) async {
    await _client.from('channel_quotes').delete().eq('channel_id', channelId);
    if (decrees.isEmpty) return;
    await _client.from('channel_quotes').insert([
      for (var i = 0; i < decrees.length; i++)
        {
          'channel_id': channelId,
          'text': decrees[i].text,
          'target_per_day': decrees[i].targetPerDay,
          'window_start_min': decrees[i].windowStartMin,
          'window_end_min': decrees[i].windowEndMin,
          'position': i,
        }
    ]);
  }

  // ------------------------------------------------------------ managing

  /// All members with display names and roles.
  Future<List<ChannelMemberInfo>> fetchMembers(String channelId) async {
    final rows = await _client
        .from('channel_memberships')
        .select('user_id, role, profiles(display_name)')
        .eq('channel_id', channelId);
    return rows.map((r) {
      final profile = r['profiles'] as Map<String, dynamic>?;
      return ChannelMemberInfo(
        userId: r['user_id'] as String,
        displayName:
            (profile?['display_name'] as String?) ?? 'Decree Reader',
        role: (r['role'] as String?) ?? 'member',
      );
    }).toList()
      ..sort((a, b) {
        int rank(String role) =>
            role == 'owner' ? 0 : (role == 'admin' ? 1 : 2);
        return rank(a.role).compareTo(rank(b.role));
      });
  }

  /// Owner sets a member's role. Server enforces owner-only.
  Future<void> setRole(String channelId, String userId, String role) async {
    await _client.rpc('set_member_role', params: {
      'p_channel': channelId,
      'p_user': userId,
      'p_role': role,
    });
  }

  /// Regenerates a private channel's join code. Returns the new code.
  Future<String> regenerateCode(String channelId) async {
    final res = await _client
        .rpc('regenerate_join_code', params: {'p_channel': channelId});
    return res as String;
  }

  /// Deletes a channel (owner only — RLS enforces).
  Future<void> deleteChannel(String channelId) async {
    await _client.from('channels').delete().eq('id', channelId);
  }

  /// Per-decree participation stats. Server refuses non-managers.
  Future<List<DecreeStat>> fetchStats(String channelId) async {
    final rows = await _client
        .rpc('channel_stats_for', params: {'p_channel': channelId});
    return (rows as List)
        .map((r) => DecreeStat(
              quoteId: r['quote_id'] as String,
              text: (r['decree_text'] as String?) ?? '',
              participants: (r['participants'] as int?) ?? 0,
              fullCompletions: (r['full_completions'] as int?) ?? 0,
              partial: (r['partial'] as int?) ?? 0,
            ))
        .toList();
  }

  // ------------------------------------------------------------- internal

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
      joinCode: r['join_code'] as String?,
    );
  }
}