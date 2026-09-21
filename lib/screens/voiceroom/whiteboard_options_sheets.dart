import 'package:flutter/material.dart';

import '../../models/whiteboard_item.dart';

const Color _bubble = Color(0xFF272753);
const Color _accent = Color(0xFF7B68F4);

/// What the text composer sheet hands back on Save — voice_room_detail_
/// screen.dart turns this into a WhiteboardService.addText/saveText call.
class TextDraft {
  final String text;
  final double fontSize;
  final String colorHex;
  final bool bold;
  final String textAlign;

  const TextDraft({
    required this.text,
    required this.fontSize,
    required this.colorHex,
    required this.bold,
    required this.textAlign,
  });
}

const List<String> _presetSizes = ['13', '16', '22', '30'];
const List<String> _presetSizeLabels = ['S', 'M', 'L', 'XL'];

// 8-hex ARGB — see WhiteboardItem.colorHex's doc comment.
const List<String> _presetColors = [
  'FFFFFFFF', // white
  'FF1A1A1F', // near-black
  'FF7B68F4', // purple accent
  'FFFF4757', // red
  'FFFFC107', // amber
  'FF2ECC71', // green
  'FF4FA8FF', // blue
  'FFFF7AB6', // pink
];

/// Add-or-edit sheet for a board text item: wording plus font size, color,
/// bold, and alignment, all previewed live in the text field itself as you
/// change them. Pass [existing] to edit an item in place — that also
/// reveals the z-order/delete row, which a brand-new item (nothing to
/// reorder or delete yet) doesn't need.
Future<void> showTextComposerSheet(
  BuildContext context, {
  WhiteboardItem? existing,
  required void Function(TextDraft draft) onSave,
  VoidCallback? onDelete,
  VoidCallback? onBringToFront,
  VoidCallback? onSendToBack,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: _bubble,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _TextComposerSheet(
      existing: existing,
      onSave: onSave,
      onDelete: onDelete,
      onBringToFront: onBringToFront,
      onSendToBack: onSendToBack,
    ),
  );
}

class _TextComposerSheet extends StatefulWidget {
  final WhiteboardItem? existing;
  final void Function(TextDraft draft) onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onBringToFront;
  final VoidCallback? onSendToBack;

  const _TextComposerSheet({
    required this.existing,
    required this.onSave,
    this.onDelete,
    this.onBringToFront,
    this.onSendToBack,
  });

  @override
  State<_TextComposerSheet> createState() => _TextComposerSheetState();
}

class _TextComposerSheetState extends State<_TextComposerSheet> {
  late final _controller = TextEditingController(text: widget.existing?.text ?? '');
  late double _fontSize = widget.existing?.fontSize ?? 16;
  late String _colorHex = widget.existing?.colorHex ?? 'FFFFFFFF';
  late bool _bold = widget.existing?.bold ?? false;
  late String _textAlign = widget.existing?.textAlign ?? 'left';

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _currentColor {
    try {
      return Color(int.parse('0x$_colorHex'));
    } catch (_) {
      return Colors.white;
    }
  }

  TextAlign get _flutterTextAlign => switch (_textAlign) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      };

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSave(
      TextDraft(text: text, fontSize: _fontSize, colorHex: _colorHex, bold: _bold, textAlign: _textAlign),
    );
  }

  void _runThenClose(VoidCallback? action) {
    if (action == null) return;
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? 'Edit text' : 'Add text to the board',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),
              // The field itself previews every style choice below live —
              // what you see here is what lands on the board.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 6,
                  textAlign: _flutterTextAlign,
                  style: TextStyle(
                    color: _currentColor,
                    fontSize: _fontSize,
                    fontWeight: _bold ? FontWeight.w800 : FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Say something...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _label('Size'),
              const SizedBox(height: 6),
              Row(
                children: List.generate(_presetSizes.length, (i) {
                  final size = double.parse(_presetSizes[i]);
                  final selected = _fontSize == size;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _pillButton(
                      label: _presetSizeLabels[i],
                      selected: selected,
                      onTap: () => setState(() => _fontSize = size),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              _label('Color'),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _presetColors.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final hex = _presetColors[i];
                    final selected = _colorHex == hex;
                    Color swatch;
                    try {
                      swatch = Color(int.parse('0x$hex'));
                    } catch (_) {
                      swatch = Colors.white;
                    }
                    return GestureDetector(
                      onTap: () => setState(() => _colorHex = hex),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: swatch,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? _accent : Colors.white24, width: selected ? 2.5 : 1),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _pillButton(
                    label: 'B',
                    bold: true,
                    selected: _bold,
                    onTap: () => setState(() => _bold = !_bold),
                  ),
                  const SizedBox(width: 12),
                  _alignButton(Icons.format_align_left_rounded, 'left'),
                  _alignButton(Icons.format_align_center_rounded, 'center'),
                  _alignButton(Icons.format_align_right_rounded, 'right'),
                ],
              ),
              if (_isEditing) ...[
                const Divider(color: Colors.white12, height: 28),
                Row(
                  children: [
                    Expanded(
                      child: _OptionButton(
                        icon: Icons.flip_to_front_rounded,
                        label: 'Bring to front',
                        dense: true,
                        onTap: () => _runThenClose(widget.onBringToFront),
                      ),
                    ),
                    Expanded(
                      child: _OptionButton(
                        icon: Icons.flip_to_back_rounded,
                        label: 'Send to back',
                        dense: true,
                        onTap: () => _runThenClose(widget.onSendToBack),
                      ),
                    ),
                  ],
                ),
                _OptionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: Colors.redAccent,
                  dense: true,
                  onTap: () => _runThenClose(widget.onDelete),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: Text(_isEditing ? 'Save' : 'Add to board', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w700),
      );

  /// A plain custom pill instead of Flutter's ChoiceChip — the app's
  /// ambient (light) Material theme was overriding ChoiceChip's label
  /// color on this dark sheet, leaving the unselected Size/Bold chips
  /// rendering as blank white boxes with invisible text. This sidesteps
  /// Material chip theming entirely, the same way _alignButton already
  /// does for the alignment icons below.
  Widget _pillButton({required String label, required bool selected, required VoidCallback onTap, bool bold = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 38),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _accent : Colors.white30, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: bold || selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _alignButton(IconData icon, String value) {
    final selected = _textAlign == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _textAlign = value),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? _accent : Colors.white30, width: 1),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Options sheet for a board image: rotate, reorder, delete — no wording or
/// text styling to offer, unlike the text composer above.
void showImageOptionsSheet(
  BuildContext context, {
  required VoidCallback onRotate,
  required VoidCallback onBringToFront,
  required VoidCallback onSendToBack,
  required VoidCallback onDelete,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: _bubble,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Image options',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _OptionButton(
              icon: Icons.rotate_right_rounded,
              label: 'Rotate 90°',
              onTap: () {
                Navigator.of(sheetContext).pop();
                onRotate();
              },
            ),
            _OptionButton(
              icon: Icons.flip_to_front_rounded,
              label: 'Bring to front',
              onTap: () {
                Navigator.of(sheetContext).pop();
                onBringToFront();
              },
            ),
            _OptionButton(
              icon: Icons.flip_to_back_rounded,
              label: 'Send to back',
              onTap: () {
                Navigator.of(sheetContext).pop();
                onSendToBack();
              },
            ),
            const Divider(color: Colors.white12, height: 20),
            _OptionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: Colors.redAccent,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onDelete();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool dense;
  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
