import 'package:flutter/material.dart';

/// The app-wide messenger. Pass it to MaterialApp.scaffoldMessengerKey (see
/// main.dart) so ANY code, including AppState, can show a short message
/// without needing a screen's context.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows a short message at the bottom of the screen, replacing any message
/// that is still showing so toasts never queue up.
void showToast(String message) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
