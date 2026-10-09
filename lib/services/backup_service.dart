// backup_service.dart
// Uploads the user's personal state snapshot to Supabase and restores it
// on a fresh install / new device.
//
// Design (agreed in planning):
// - The payload is AppState's own JSON (its _toJson output) stored in
//   user_backups.payload as jsonb. One row per user — a snapshot, not an
//   event log.
// - Upload is debounced and fire-and-forget: a failed upload must never
//   disturb the app. Local data remains the source of truth.
// - Restore MERGES rather than overwrites: local data can be newer than
//   the backup (user made decrees after clearing cache, or uses two
//   devices). Merge rules live in AppState.mergeBackup.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackupService {
  BackupService(this._client);

  final SupabaseClient _client;
  Timer? _debounce;
  Future<void>? _inFlight;

  bool get _signedIn => _client.auth.currentUser != null;

  /// Call after every local save. Debounces to at most one upload per
  /// [interval], so rapid reads/edices don't spam the network.
  void scheduleUpload(
    Map<String, dynamic> payload, {
    Duration interval = const Duration(seconds: 30),
  }) {
    if (!_signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(interval, () => uploadNow(payload));
  }

  /// Immediate upload. Never throws; logs failures for diagnosis.
  Future<void> uploadNow(Map<String, dynamic> payload) async {
    if (!_signedIn) return;
    // Collapse overlapping uploads: if one is running, wait for it.
    if (_inFlight != null) {
      await _inFlight;
    }
    _inFlight = _doUpload(payload);
    try {
      await _inFlight;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _doUpload(Map<String, dynamic> payload) async {
    try {
      await _client.from('user_backups').upsert({
        'user_id': _client.auth.currentUser!.id,
        'payload': payload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Backup upload failed (will retry on next save): $e');
    }
  }

  /// Fetches the stored backup, or null if none exists / fetch fails.
  /// Returns the raw JSON payload exactly as AppState saved it.
  Future<Map<String, dynamic>?> fetch() async {
    if (!_signedIn) return null;
    try {
      final row = await _client
          .from('user_backups')
          .select('payload')
          .eq('user_id', _client.auth.currentUser!.id)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row['payload'] as Map);
    } catch (e) {
      debugPrint('Backup fetch failed: $e');
      return null;
    }
  }

  /// Final upload before sign-out (call BEFORE AuthService.signOut).
  Future<void> flushBeforeSignOut(Map<String, dynamic> payload) async {
    _debounce?.cancel();
    await uploadNow(payload);
  }
}