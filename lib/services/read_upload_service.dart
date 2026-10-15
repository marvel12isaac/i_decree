// read_upload_service.dart
// Uploads channel-decree reads to Supabase (read_events table).
//
// Rules (agreed):
// - Only reads of JOINED channels' decrees are uploaded. Personal decree
//   reads never leave the device.
// - An upload failure must never disturb the reading experience. It is
//   logged and reported back as `false`; AppState keeps the read in a
//   pending list and tries again when the phone is back online.
// - The local _reads map in AppState remains the single source of truth
//   for the user's own streaks. This service is purely for creator stats.
//
// The upsert is a CUMULATIVE count: we send the user's total reads for
// that quote that day (from local state), so retries and replays are
// naturally idempotent — the last successful write is always correct.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReadUploadService {
  ReadUploadService(this._client);

  final SupabaseClient _client;

  /// Records that [userId] read the channel decree [quoteId] (in channel
  /// [channelId]) [countForToday] times so far today. Cumulative upsert.
  /// Returns true when the server accepted it, false otherwise.
  Future<bool> uploadRead({
    required String quoteId,
    required String channelId,
    required String userId,
    required String dayKey, // yyyy-MM-dd, device-local calendar day
    required int countForToday,
  }) async {
    try {
      await _client.from('read_events').upsert(
        {
          'quote_id': quoteId,
          'channel_id': channelId,
          'user_id': userId,
          'day': dayKey,
          'read_count': countForToday,
        },
        onConflict: 'quote_id,user_id,day',
      );
      return true;
    } catch (e) {
      // Never disturb the reader. The most common cause is being offline.
      debugPrint('Read upload failed (will retry): $e');
      return false;
    }
  }
}