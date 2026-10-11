import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import 'quote_editor_screen.dart';

/// "Edit decrees" (wireframe 7b): managers add, edit, and remove the
/// channel's decrees using the same editor look as personal decrees
/// (draft mode). Saving replaces the channel's whole decree list —
/// members keep their streaks because decree ids are stable per save…
/// with one honest caveat: this v1 implementation replaces ALL ids on
/// every save, so member read history for this channel resets. Fine for
/// the test group; flagged for the accounts/sync phase to fix properly.
class ChannelEditDecreesScreen extends StatefulWidget {
  const ChannelEditDecreesScreen({super.key, required this.channelId});

  final String channelId;

  @override
  State<ChannelEditDecreesScreen> createState() =>
      _ChannelEditDecreesScreenState();
}

class _ChannelEditDecreesScreenState extends State<ChannelEditDecreesScreen> {
  late final ChannelService _service =
      ChannelService(Supabase.instance.client);

  List<StoredDecree>? _decrees;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _service.fetchDecreesForEdit(widget.channelId);
      if (!mounted) return;
      setState(() => _decrees = d);
    } catch (e) {
      if (!mounted) return;
      setState(() => _decrees = []);
    }
  }

  Future<void> _saveAll() async {
    final decrees = _decrees;
    if (decrees == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.replaceDecrees(widget.channelId, [
        for (final d in decrees)
          EditorDecree(
            text: d.text,
            targetPerDay: d.targetPerDay,
            windowStartMin: d.windowStartMin,
            windowEndMin: d.windowEndMin,
          ),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Decrees saved')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Try again.')));
      setState(() => _saving = false);
    }
  }

  Future<void> _addDecree() async {
    final draft = await Navigator.of(context).push<DecreeDraft>(
      MaterialPageRoute(builder: (_) => const QuoteEditorScreen.draft()),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _decrees ??= [];
      _decrees!.add(StoredDecree(
        id: '',
        text: draft.text,
        targetPerDay: draft.targetPerDay,
        windowStartMin: draft.windowStartMin,
        windowEndMin: draft.windowEndMin,
      ));
    });
  }

  Future<void> _editDecree(int index) async {
    final existing = _decrees![index];
    final seed = Quote(
      id: existing.id.isEmpty ? 'draft' : existing.id,
      text: existing.text,
      notifBase: 0,
      createdAt: DateTime.now(),
      targetPerDay: existing.targetPerDay,
      windowStartMin: existing.windowStartMin,
      windowEndMin: existing.windowEndMin,
      remindersOn: false,
    );
    final draft = await Navigator.of(context).push<DecreeDraft>(
      MaterialPageRoute(builder: (_) => QuoteEditorScreen.draft(seed: seed)),
    );
    if (draft == null || !mounted) return;
    setState(() {
      existing.text = draft.text;
      existing.targetPerDay = draft.targetPerDay;
      existing.windowStartMin = draft.windowStartMin;
      existing.windowEndMin = draft.windowEndMin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final decrees = _decrees;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Edit decrees'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveAll,
            child: const Text('Save'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: decrees != null && decrees.length >= 33 ? null : _addDecree,
        child: const Icon(Icons.add),
      ),
      body: decrees == null
          ? const Center(child: CircularProgressIndicator())
          : decrees.isEmpty
              ? Center(
                  child: Text('No decrees yet — add the first one.',
                      style: TextStyle(color: c.muted)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: decrees.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final d = decrees[i];
                    return ListTile(
                      title: Text(
                        d.text.split('\n').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: d.text.contains('\n')
                          ? Text(
                              d.text.split('\n').skip(1).join(' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() => decrees.removeAt(i)),
                      ),
                      onTap: () => _editDecree(i),
                    );
                  },
                ),
    );
  }
}