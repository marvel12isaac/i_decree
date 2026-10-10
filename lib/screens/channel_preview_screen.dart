import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import '../app_state.dart';
import '../widgets/sign_in_sheet.dart';
import 'circle_quote_list_screen.dart';

/// Wireframe 3: a read-only preview of a channel the user has NOT joined.
/// Shows the decrees with a Join banner. Joining itself is built in the
/// next step — the button explains that for now.
class ChannelPreviewScreen extends StatefulWidget {
  const ChannelPreviewScreen({super.key, required this.channel, this.preloaded});

  final ChannelSummary channel;

  /// Already-fetched decrees (code-match path). Null → fetch normally.
  final List<ChannelDecreePreview>? preloaded;

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
    if (widget.preloaded != null) {
      _decrees = widget.preloaded;
    } else {
      _load();
    }
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
          // Join banner (wireframe 3) — hidden when already a member.
          if (!AppScope.of(context).isMemberOf(widget.channel.id))
            Container(
              color: c.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

  Future<void> _onJoinPressed() async {
    final state = AppScope.of(context);
    if (!state.isSignedIn) {
      final ok = await showSignInSheet(context, state);
      if (!ok || !mounted) return;
    }
    try {
      await state.joinPublicChannel(widget.channel.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined ${widget.channel.name}!')),
      );
      // Land IN the channel, not back on search results: pop to Home,
      // then open the channel's decree list.
      Navigator.of(context).popUntil((r) => r.isFirst);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CircleQuoteListScreen(circleId: widget.channel.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not join. Try again.')),
      );
    }
  }
}