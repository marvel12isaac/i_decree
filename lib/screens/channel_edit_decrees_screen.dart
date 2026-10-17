import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import '../widgets/offline_banner.dart';
import '../widgets/swipe_to_delete.dart';
import '../widgets/toast.dart';
import 'quote_editor_screen.dart';

/// "Edit decrees" (wireframe 7b): managers add, edit, and remove the
/// channel's decrees using the same editor look as personal decrees
/// (draft mode). Saving updates existing decrees in place (same ids), adds
/// new ones and deletes removed ones, so members keep their read history and
/// reminder choices for every decree that stays.
///
/// Removing a decree (the X, or swipe left and tap the trash) only takes it
/// out of the draft. Nothing is deleted until Save, and Save asks first when
/// it would delete anything for all members.
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
  bool _loadFailed = false;

  /// Ids of the decrees that existed when the list loaded. Used to count how
  /// many Save would delete (new, unsaved decrees have no id yet).
  Set<String> _originalIds = {};

  /// The id of the row whose trash button is showing (null = none).
  final ValueNotifier<String?> _openRow = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _openRow.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _service.fetchDecreesForEdit(widget.channelId);
      if (!mounted) return;
      setState(() {
        _decrees = d;
        _originalIds = d.map((x) => x.id).toSet();
      });
    } catch (e) {
      if (!mounted) return;
      // Keep the list null (not empty): saving an empty list would delete
      // every decree, so Save and Add stay off until the list really loads.
      setState(() => _loadFailed = true);
    }
  }

  /// How many saved decrees are missing from the draft (what Save deletes).
  int _removedCount(List<StoredDecree> decrees) {
    final kept = decrees.map((d) => d.id).toSet();
    return _originalIds.where((id) => !kept.contains(id)).length;
  }

  /// Asks before Save deletes decrees for every member. Cancel keeps the
  /// draft as it is.
  Future<bool> _confirmRemoval(int n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 1 ? 'Remove 1 decree?' : 'Remove $n decrees?'),
        content: Text(
          n == 1
              ? 'This decree will be removed for all members. '
                  'This can\u2019t be undone.'
              : 'These $n decrees will be removed for all members. '
                  'This can\u2019t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: Palette.danger)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _saveAll() async {
    final decrees = _decrees;
    if (decrees == null || _saving) return;
    final state = AppScope.of(context);
    final removed = _removedCount(decrees);
    if (removed > 0) {
      final ok = await _confirmRemoval(removed);
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await _service.saveDecrees(widget.channelId, decrees);
      if (!mounted) return;
      showToast(removed > 0
          ? 'Decrees saved \u00b7 $removed removed'
          : 'Decrees saved.');
      Navigator.of(context).pop();
    } catch (e) {
      final online = await state.checkConnection();
      if (!mounted) return;
      showToast(online ? 'Could not save. Try again.' : offlineActionMessage);
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
        onPressed:
            decrees == null || decrees.length >= 33 ? null : _addDecree,
        child: const Icon(Icons.add),
      ),
      body: _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load this channel\u2019s decrees. '
                      'Check your connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() => _loadFailed = false);
                        _load();
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : decrees == null
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
                    // ObjectKey: new decrees all have an empty id.
                    return SwipeToDelete(
                      key: ObjectKey(d),
                      id: d.id.isEmpty ? 'new-${identityHashCode(d)}' : d.id,
                      openRow: _openRow,
                      // Staged only: nothing is deleted until Save.
                      onDelete: () async {
                        setState(() => decrees.remove(d));
                        return true;
                      },
                      child: ListTile(
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
                          onPressed: () => setState(() => decrees.remove(d)),
                        ),
                        onTap: () => _editDecree(i),
                      ),
                    );
                  },
                ),
    );
  }
}