import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/channel_service.dart';
import '../theme.dart';

/// Creator view (per the brief): per-decree participation, full and
/// partial completions. The server refuses non-managers.
class ChannelStatsScreen extends StatefulWidget {
  const ChannelStatsScreen({super.key, required this.channelId});

  final String channelId;

  @override
  State<ChannelStatsScreen> createState() => _ChannelStatsScreenState();
}

class _ChannelStatsScreenState extends State<ChannelStatsScreen> {
  late final ChannelService _service =
      ChannelService(Supabase.instance.client);

  List<DecreeStat>? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _service.fetchStats(widget.channelId);
      if (!mounted) return;
      setState(() => _stats = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Stats are visible to channel managers only.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Participation stats')),
      body: _stats == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted)),
                  ),
                )
              : _stats!.isEmpty
                  ? Center(
                      child: Text('No decrees in this channel.',
                          style: TextStyle(color: c.muted)))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _stats!.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        final s = _stats![i];
                        final title =
                            s.text.split('\n').first;
                        return ListTile(
                          title: Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _statChip(context, 'Participating',
                                    s.participants, c.teal),
                                _statChip(context, 'Completed',
                                    s.fullCompletions, c.blue),
                                _statChip(
                                    context, 'Partial', s.partial, c.flame),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _statChip(
      BuildContext context, String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}