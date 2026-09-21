import 'package:flutter/material.dart';

/// One row in a [showDarkActionSheet] list.
class DarkActionItem {
  final String label;
  // null = the sheet's default (white) text color; pass a color (e.g. red)
  // for a destructive action.
  final Color? color;
  final bool enabled;
  // Shown under the label, smaller/dimmer, only while [enabled] is false —
  // explains why this action isn't available right now.
  final String? disabledHint;
  final VoidCallback onTap;

  const DarkActionItem({
    required this.label,
    this.color,
    this.enabled = true,
    this.disabledHint,
    required this.onTap,
  });
}

/// A minimal centered-text action sheet — no icons, thin dividers, a
/// near-black card, and a full-width purple "Cancel" pill below. Used
/// anywhere in the voice room screens that needs a short list of actions
/// in this exact look (see voice_room_detail_screen.dart's "…" room menu
/// and room_profile_sheet.dart's per-participant "…" menu) so the two stay
/// visually identical instead of drifting into two similar-but-not-quite
/// versions of the same design.
Future<void> showDarkActionSheet(
  BuildContext context, {
  required List<DarkActionItem> items,
  String cancelLabel = 'Cancel',
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _DarkActionSheet(items: items, cancelLabel: cancelLabel),
  );
}

class _DarkActionSheet extends StatelessWidget {
  final List<DarkActionItem> items;
  final String cancelLabel;
  const _DarkActionSheet({required this.items, required this.cancelLabel});

  static const _cardColor = Color(0xFF1C1C22);
  static const _accent = Color(0xFF7B68F4);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(14)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: Colors.white12),
                    _DarkActionRow(item: items[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: Text(cancelLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkActionRow extends StatelessWidget {
  final DarkActionItem item;
  const _DarkActionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final textColor = !item.enabled ? Colors.white24 : (item.color ?? Colors.white);
    return InkWell(
      // Closes the sheet itself before running the action, so every caller
      // gets that "tap an option, sheet closes, action happens" feel for
      // free instead of having to remember to pop a sheet-scoped context
      // in every single item's onTap.
      onTap: item.enabled
          ? () {
              Navigator.of(context).pop();
              item.onTap();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
            ),
            if (!item.enabled && item.disabledHint != null) ...[
              const SizedBox(height: 3),
              Text(
                item.disabledHint!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
