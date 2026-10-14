import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../services/channel_service.dart';
import '../theme.dart';
import 'sign_in_sheet.dart';

/// What is being reported: a whole channel, or one decree in it.
class ReportTarget {
  const ReportTarget.channel({required this.channelId}) : quoteId = null;

  const ReportTarget.decree({required this.channelId, required this.quoteId});

  final String channelId;

  /// The channel decree's id; null when the whole channel is reported.
  final String? quoteId;

  bool get isDecree => quoteId != null;
}

/// Wireframes 9 and 9b: reasons (spam / inappropriate / other), an optional
/// comment, and a note that the iDecree team reviews reports. Asks the user
/// to sign in first (a report needs a reporter). Returns true when a report
/// was sent.
Future<bool> showReportDialog(
  BuildContext context,
  AppState state,
  ReportTarget target,
) async {
  // Only members can report (the database enforces this too).
  if (state.isSignedIn && !state.isMemberOf(target.channelId)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Join this channel to report it.')),
    );
    return false;
  }
  if (!state.isSignedIn) {
    final ok =
        await showSignInSheet(context, state, title: 'Sign in to report.');
    if (!ok || !context.mounted) return false;
  }
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(target: target),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Thanks. Reports are reviewed by the iDecree team.')),
    );
  }
  return sent ?? false;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.target});

  final ReportTarget target;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  // Values match the check constraint on reports.reason.
  static const Map<String, String> _reasons = {
    'spam': 'Spam',
    'inappropriate': 'Inappropriate content',
    'other': 'Other',
  };

  final TextEditingController _comment = TextEditingController();
  String _reason = 'spam';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await ChannelService(Supabase.instance.client).fileReport(
        channelId: widget.target.channelId,
        quoteId: widget.target.quoteId,
        reason: _reason,
        comment: _comment.text,
      );
      if (!mounted) return;
      switch (outcome) {
        case ReportOutcome.sent:
          Navigator.of(context).pop(true);
          break;
        case ReportOutcome.alreadyReported:
          setState(() {
            _busy = false;
            _error = widget.target.isDecree
                ? 'You\u2019ve already reported this decree.'
                : 'You\u2019ve already reported this channel.';
          });
          break;
        case ReportOutcome.limitReached:
          setState(() {
            _busy = false;
            _error = 'You\u2019ve reached the report limit for this channel.';
          });
          break;
      }
    } catch (e) {
      debugPrint('Report failed: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not send the report. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: Text(widget.target.isDecree
          ? 'Report this decree'
          : 'Report this channel'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in _reasons.entries)
              Semantics(
                selected: _reason == entry.key,
                inMutuallyExclusiveGroup: true,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _reason == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _reason == entry.key ? c.teal : c.muted,
                  ),
                  title: Text(entry.value),
                  onTap: _busy
                      ? null
                      : () => setState(() => _reason = entry.key),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: c.overdue, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Text(
              'Reports are reviewed by the iDecree team.',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Sending…' : 'Submit'),
        ),
      ],
    );
  }
}