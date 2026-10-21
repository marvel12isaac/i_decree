import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme.dart';
import 'fx_widgets.dart';
import 'toast.dart';

/// A small "Update available" card for the top of Home. It starts the (at
/// most once a day) update check a few seconds after Home appears, so the
/// check never competes with start-up. Ordinary updates can be dismissed;
/// a mandatory one (installed version below the minimum) cannot.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) unawaited(UpdateService.check());
    });
  }

  Future<void> _open(UpdateInfo info) async {
    final ok = await UpdateService.open(info);
    if (!ok) showToast('Could not open the link. Try again later.');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: UpdateService.pending,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final c = AppColors.of(context);
        final notes = info.notes?.trim();
        return FadeSlideIn(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: c.teal.withAlpha(31),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.teal),
              ),
              child: Row(
                children: [
                  Icon(Icons.system_update_alt, color: c.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.isMandatory
                              ? 'Update required'
                              : 'Update available \u00b7 v${info.latest}',
                          style: TextStyle(
                            color: c.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (notes != null && notes.isNotEmpty)
                          Text(
                            notes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _open(info),
                    child: const Text('Update'),
                  ),
                  if (!info.isMandatory)
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: Icon(Icons.close, size: 20, color: c.muted),
                      onPressed: () => UpdateService.dismiss(info),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}