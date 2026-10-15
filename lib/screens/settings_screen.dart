import 'package:flutter/material.dart';

import '../theme.dart';

/// Settings. Empty for now: the Home menu already opens it, so the options
/// can be added here one by one.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'More settings coming soon.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 16),
          ),
        ),
      ),
    );
  }
}