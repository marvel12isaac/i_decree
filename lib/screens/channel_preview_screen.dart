import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/channel_service.dart';
import '../theme.dart';

/// Wireframe 3: a read-only preview of a channel the user has NOT joined.
/// Shows the decrees with a Join banner. Joining itself is built in the
/// next step — the button explains that for now.
class ChannelPreviewScreen extends StatefulWidget {
  const ChannelPreviewScreen({super.key, required this.channel});

  final ChannelSummary channel;

  @override
  State<ChannelPreviewScreen> createState() => _ChannelPreviewScreenState();
}

class _ChannelPreviewScreenState extends State<ChannelPreviewScreen> {
  late final ChannelService _service = ChannelService(Supabase.instance.client);

  List<ChannelDecreePreview>? _decrees;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _service.fetchDecrees(widget.channel.id);
      if (!mounted) return;
      setState(() => _decrees = d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load this channel. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final decrees = _decrees;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.channel.name,
                style: const TextStyle(fontSize: 17)),
            Text(
              '${widget.channel.memberCount} members · '
              '${widget.channel.decreesCount} decrees',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Join banner (wireframe 3).
          Container(
            color: c.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Preview — Join to add this channel to your feed',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
                FilledButton(
                  onPressed: _onJoinPressed,
                  child: const Text('Join'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(c, decrees)),
        ],
      ),
    );
  }

  Widget _buildBody(AppColors c, List<ChannelDecreePreview>? decrees) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center,
              style: TextStyle(color: c.muted)),
        ),
      );
    }
    if (decrees == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (decrees.isEmpty) {
      return Center(
        child: Text('No decrees in this channel yet.',
            style: TextStyle(color: c.muted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: decrees.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, i) {
        final d = decrees[i];
        final breakAt = d.text.indexOf('\n');
        final title = breakAt < 0 ? d.text : d.text.substring(0, breakAt).trim();
        final body =
            breakAt < 0 ? '' : d.text.substring(breakAt + 1).trim();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.muted)),
              ],
            ],
          ),
        );
      },
    );
  }

  void _onJoinPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Joining channels arrives in the next update.'),
      ),
    );
  }
}