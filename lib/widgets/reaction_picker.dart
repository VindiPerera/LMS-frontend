import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The 5 reactions every moment can carry. Order matches the spec: like,
/// laugh, wow, sad, angry.
const List<String> kReactionEmojis = ['❤️', '😂', '😮', '😢', '😡'];

/// Inserts an animated emoji row into the nearest [Overlay], anchored above
/// [anchor] (pass the like button's global center — long-press position
/// works too). Call from moment_card.dart's `onLongPress` handler.
void showReactionPicker(
  BuildContext context, {
  required Offset anchor,
  required ValueChanged<String> onSelect,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  void dismiss() => entry.remove();

  entry = OverlayEntry(
    builder: (_) => _ReactionPickerOverlay(
      anchor: anchor,
      onDismiss: dismiss,
      onSelect: (emoji) {
        onSelect(emoji);
        dismiss();
      },
    ),
  );
  overlay.insert(entry);
}

class _ReactionPickerOverlay extends StatefulWidget {
  final Offset anchor;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  const _ReactionPickerOverlay({
    required this.anchor,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_ReactionPickerOverlay> createState() => _ReactionPickerOverlayState();
}

class _ReactionPickerOverlayState extends State<_ReactionPickerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const pickerWidth = 260.0;
    final left = (widget.anchor.dx - pickerWidth / 2)
        .clamp(12.0, size.width - pickerWidth - 12.0);
    final top = (widget.anchor.dy - 72).clamp(24.0, size.height - 100.0);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
            alignment: Alignment.bottomCenter,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(28),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: kReactionEmojis
                      .map((emoji) => _EmojiButton(
                            emoji: emoji,
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              widget.onSelect(emoji);
                            },
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmojiButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiButton({required this.emoji, required this.onTap});

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 1.35 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}
