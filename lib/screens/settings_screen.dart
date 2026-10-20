import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/fx_widgets.dart';

/// Settings. Effects is the first option; more can be added below it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const EffectsPicker(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'More settings coming soon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}