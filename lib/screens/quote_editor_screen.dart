import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// Add a new quote (quote == null) or edit an existing one.
/// Pops with `true` if the quote was deleted, so the caller can close too.
///
/// When adding a new quote, [prefill] (if given) seeds the initial text and
/// settings instead of starting blank — used by "Add to My Decrees" to copy
/// a channel decree in without saving it until the user confirms here.
/// Ignored when [quote] is set (editing an existing decree).
///
/// Draft mode ([QuoteEditorScreen.draft]): used by the channel editor for
/// decree entries. Identical look, but Save pops with a [DecreeDraft]
/// instead of storing anything, and the reminder-time section is hidden
/// (channel decrees use default windows; the per-day target is kept).
class QuoteEditorScreen extends StatefulWidget {
  const QuoteEditorScreen({super.key, this.quote, this.prefill})
      : draftMode = false,
        seed = null;

  const QuoteEditorScreen.draft({super.key, this.seed})
      : draftMode = true,
        quote = null,
        prefill = null;

  final Quote? quote;
  final Quote? prefill;

  /// Seeds a draft (draft mode only).
  final Quote? seed;
  final bool draftMode;

  @override
  State<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _QuoteEditorScreenState extends State<QuoteEditorScreen> {
  /// The last minute of the day. Midnight at the END of a window is saved as
  /// this, so the read still counts for the day it belongs to (a read at
  /// 12:00 AM would count for the next day).
  static const int _lastMinute = 23 * 60 + 59;

  late final TextEditingController _text;
  late int _target;
  late int _startMin;
  late int _endMin;
  late bool _remindersOn;

  /// True when the end time was midnight and was saved as 11:59 PM, so a
  /// short note explains the change.
  bool _midnightEnd = false;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.quote ?? widget.prefill ?? widget.seed;
    _text = TextEditingController(text: seed?.text ?? '');
    _target = seed?.targetPerDay ?? 1;
    final start = seed?.windowStartMin ?? 8 * 60;
    final end = seed?.windowEndMin ?? 20 * 60;
    // Older data (and some channel decrees) store midnight at the end of the
    // day as 24:00, which has no clock face. Treat it as 11:59 PM.
    _midnightEnd = end > _lastMinute;
    _startMin = start.clamp(0, _lastMinute).toInt();
    _endMin = end.clamp(0, _lastMinute).toInt();
    _remindersOn = seed?.remindersOn ?? true;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  TimeOfDay _toTime(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTime(start ? _startMin : _endMin),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (start) {
        _startMin = minutes;
      } else if (minutes == 0) {
        // 12:00 AM as the last time means the end of the day.
        _endMin = _lastMinute;
        _midnightEnd = true;
      } else {
        _endMin = minutes;
        _midnightEnd = false;
      }
    });
  }

  /// The note shown under the last-time row when midnight was chosen.
  List<Widget> _midnightNote() => [
        if (_target > 1 && _midnightEnd)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Midnight is saved as 11:59 PM so the read counts for the '
              'same day.',
              style: TextStyle(color: Palette.muted),
            ),
          ),
      ];

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write your decree first.');
      return;
    }
    if (_target > 1 && _endMin <= _startMin) {
      setState(() => _error = 'Choose an end time after the start time.');
      return;
    }

    // Draft mode: hand the decree back to the caller, store nothing.
    if (widget.draftMode) {
      Navigator.of(context).pop(DecreeDraft(
        text: text,
        targetPerDay: _target,
        windowStartMin: _startMin,
        windowEndMin: _endMin,
      ));
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    final state = AppScope.of(context);
    if (_remindersOn && state.reminders.supported) {
      await state.reminders.requestPermission();
    }

    final existing = widget.quote;
    if (existing == null) {
      await state.addQuote(
        text: text,
        targetPerDay: _target,
        windowStartMin: _startMin,
        windowEndMin: _endMin,
        remindersOn: _remindersOn,
      );
    } else {
      await state.updateQuote(
        existing.id,
        text: text,
        targetPerDay: _target,
        windowStartMin: _startMin,
        windowEndMin: _endMin,
        remindersOn: _remindersOn,
      );
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _delete() async {
    final existing = widget.quote;
    if (existing == null) return;
    final confirmed = await confirmDelete(context);
    if (!confirmed || !mounted) return;
    await AppScope.of(context).deleteQuote(existing.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isNew = widget.quote == null;
    final isCopy = isNew && widget.prefill != null;
    final title = widget.draftMode
        ? 'Channel Decree'
        : widget.quote != null
            ? 'Edit Decree'
            : isCopy
                ? 'Add to My Decrees'
                : 'New Decree';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            TextField(
              controller: _text,
              minLines: 5,
              maxLines: null,
              maxLength: widget.draftMode ? 1000 : 2000,
              textCapitalization: TextCapitalization.sentences,
              style: quoteStyle(size: 18),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    'Write or paste your decree here. You can edit it later.',
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text('Times to read each day',
                      style: TextStyle(fontSize: 16)),
                ),
                IconButton(
                  tooltip: 'Fewer',
                  onPressed:
                      _target > 1 ? () => setState(() => _target--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 32,
                  child: Text('$_target',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'More',
                  onPressed: _target < Quote.maxPerDay
                      ? () => setState(() => _target++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (widget.draftMode) ...[
              // Channel decrees carry a daily period (window) that members'
              // crowns, stats and optional reminders derive from. No
              // "Remind me" switch here — that's each member's choice.
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_target == 1 ? 'Decree time' : 'First decree time'),
                trailing: Text(_toTime(_startMin).format(context),
                    style: const TextStyle(fontSize: 16)),
                onTap: () => _pickTime(start: true),
              ),
              if (_target > 1)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Last decree time'),
                  trailing: Text(_toTime(_endMin).format(context),
                      style: const TextStyle(fontSize: 16)),
                  onTap: () => _pickTime(start: false),
                ),
              ..._midnightNote(),
              if (_target > 1)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Reads are spread evenly between the first and last time.',
                    style: TextStyle(color: Palette.muted),
                  ),
                ),
            ],
            if (!widget.draftMode) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remind me'),
                subtitle: state.reminders.supported
                    ? null
                    : const Text(
                        'Reminders work in the Android app. Web reminders come later.'),
                value: _remindersOn,
                onChanged: (v) => setState(() => _remindersOn = v),
              ),
              if (_remindersOn) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_target == 1 ? 'Remind me at' : 'First reminder'),
                  trailing: Text(_toTime(_startMin).format(context),
                      style: const TextStyle(fontSize: 16)),
                  onTap: () => _pickTime(start: true),
                ),
                if (_target > 1)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Last reminder'),
                    trailing: Text(_toTime(_endMin).format(context),
                        style: const TextStyle(fontSize: 16)),
                    onTap: () => _pickTime(start: false),
                  ),
                ..._midnightNote(),
                if (_target > 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Reminders are spread evenly between the first and last time.',
                      style: TextStyle(color: Palette.muted),
                    ),
                  ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Palette.danger)),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                widget.draftMode
                    ? 'Done'
                    : isCopy
                        ? 'Save to My Decrees'
                        : 'Save Decree',
              ),
            ),
            if (!isNew && !widget.draftMode) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: Palette.danger),
                child: const Text('Delete Decree'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The result of a draft-mode editor session: a decree not yet stored
/// anywhere. Used by the channel editor's add/edit flow.
class DecreeDraft {
  DecreeDraft({
    required this.text,
    required this.targetPerDay,
    required this.windowStartMin,
    required this.windowEndMin,
  });

  final String text;
  final int targetPerDay;
  final int windowStartMin;
  final int windowEndMin;
}

/// Asks the user to confirm deleting a decree.
Future<bool> confirmDelete(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this Decree?'),
      content: const Text('Its streak and read history will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Palette.danger),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}