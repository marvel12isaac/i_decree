import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
// import '../services/auth_service.dart';
// import '../services/backup_service.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import '../widgets/sign_in_sheet.dart';

/// Wireframe 5: create a channel (name, description, public/private,
/// decree drafts) then wireframe 6: the share-code dialog.
class ChannelEditorScreen extends StatefulWidget {
  const ChannelEditorScreen({super.key});

  @override
  State<ChannelEditorScreen> createState() => _ChannelEditorScreenState();
}

class _ChannelEditorScreenState extends State<ChannelEditorScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _isPublic = false; // agreed default: private, join with code
  final List<EditorDecree> _decrees = [];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty && !_saving;

  Future<void> _addDecree() async {
    final text = await _decreeDialog(null);
    if (text == null || !mounted) return;
    setState(() => _decrees.add(EditorDecree(text: text)));
  }

  Future<void> _editDecree(int index) async {
    final text = await _decreeDialog(_decrees[index].text);
    if (text == null || !mounted) return;
    setState(() => _decrees[index].text = text);
  }

  Future<String?> _decreeDialog(String? existing) {
    final controller = TextEditingController(text: existing ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'New decree' : 'Edit decree'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: 'Title on the first line, body under it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;

    // Lazy sign-in: creating needs an identity.
    final state = AppScope.of(context);
    if (!state.isSignedIn) {
      final ok = await showSignInSheet(context, state);
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    final service = ChannelService(Supabase.instance.client);
    try {
      final created = await service.create(
        name: _name.text.trim(),
        description: _description.text.trim(),
        isPublic: _isPublic,
      );
      await service.replaceDecrees(created.id, _decrees);

      // Owner auto-joins: track it locally and refresh the feed.
      await state.joinCreatedChannel(created.id);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ShareCodeDialog(
          channelName: created.name,
          joinCode: created.joinCode,
        ),
      );
      if (!mounted) return;
      Navigator.of(context)
          .popUntil((r) => r.isFirst); // Home; feed now shows it
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the channel. Try again.')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('New Channel'),
        actions: [
          IconButton(
            tooltip: 'Create',
            onPressed: _canSave ? _save : null,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          TextField(
            controller: _name,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: 'Name',
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_isPublic ? 'Public channel' : 'Private channel'),
            subtitle: Text(_isPublic
                ? 'Anyone can find it in search'
                : 'Join with code only'),
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Decrees (${_decrees.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _decrees.length >= 33 ? null : _addDecree,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          for (var i = 0; i < _decrees.length; i++)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(
                  _decrees[i].text.split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: _decrees[i].text.contains('\n')
                    ? Text(
                        _decrees[i].text.split('\n').skip(1).join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editDecree(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          setState(() => _decrees.removeAt(i)),
                    ),
                  ],
                ),
                onTap: () => _editDecree(i),
              ),
            ),
          if (_decrees.length < 33)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _addDecree,
                icon: const Icon(Icons.add),
                label: const Text('Add a decree'),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create Channel'),
          ),
        ],
      ),
    );
  }
}

/// Wireframe 6: shown right after creation.
class _ShareCodeDialog extends StatelessWidget {
  const _ShareCodeDialog({
    required this.channelName,
    required this.joinCode,
  });

  final String channelName;
  final String? joinCode;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final code = joinCode;
    return AlertDialog(
      title: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 8),
          const Text('Channel created!'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (code != null) ...[
            Text('Join code', style: TextStyle(color: c.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: c.muted, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(code,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(
                    text: 'Join my "$channelName" channel on iDecree! '
                        'Open the app and search this code: $code'));
                Navigator.of(context).pop();
              },
              child: const Text('Copy invite message'),
            ),
            // Direct WhatsApp share arrives with share_plus later; a
            // clipboard invite is fully functional today.
          ] else ...[
            Text(
              '"$channelName" is public — people can find it by name in '
              'search, and you can share its name directly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}