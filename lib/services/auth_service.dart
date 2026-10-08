// auth_service.dart
// Handles Google sign-in and the Supabase session.
//
// Design (agreed in planning):
// - Lazy: nothing here runs at app startup. It is invoked only when the
//   user does something that needs a server identity (join/create channel).
// - Google Sign-In produces an ID token; Supabase verifies it and creates
//   the session. The profile row is auto-created by the DB trigger
//   (on_auth_user_created), but we update display_name from Google anyway.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  // Supabase Google provider settings — NOT the desktop client, NOT an
  // Android client).
  static const String _webClientId =
      '1055203282395-a2027gvacq1sekupjr397kimhsliua62.apps.googleusercontent.com';

  GoogleSignIn? _googleSignIn;

  GoogleSignIn get _google => _googleSignIn ??= GoogleSignIn(
        serverClientId: _webClientId,
      );

  /// Who is signed in right now? Null if signed out.
  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Signs the user in with Google. Returns the Supabase user, or null
  /// if the user cancelled the Google sheet.
  /// Throws on real failures (network, denied, misconfiguration) — the
  /// caller decides how to surface that.
  Future<User?> signInWithGoogle() async {
    final googleUser = await _google.signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in returned no ID token.');
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );

    final user = response.user;
    if (user != null) await _ensureProfile(user, googleUser);
    return user;
  }

  /// Makes sure the profile row exists and carries the Google display
  /// name. Cheap safety net alongside the DB trigger.
  Future<void> _ensureProfile(User user, GoogleSignInAccount googleUser) async {
    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'display_name': googleUser.displayName ?? 'Decree Reader',
      });
    } catch (e) {
      // Non-fatal: the trigger should have created the row already.
      debugPrint('Profile upsert failed: $e');
    }
  }

  /// Signs out locally. The server session is revoked for this device.
  /// (Backup flush before sign-out will be added with the backup service.)
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (e) {
      debugPrint('Google sign-out failed (continuing): $e');
    }
    await _client.auth.signOut();
  }

  /// Restores a previous session on app start, if one exists.
  /// Supabase persists the session automatically; this just surfaces it.
  Future<User?> restoreSession() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    // Refresh if the access token has expired (common after days away).
    try {
      await _client.auth.refreshSession();
    } catch (_) {
      // Offline or refresh failed — the stored session may still work.
    }
    return _client.auth.currentUser;
  }
}