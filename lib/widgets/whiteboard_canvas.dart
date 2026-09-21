import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/whiteboard_item.dart';
import '../services/whiteboard_service.dart';

/// A free-position canvas for a voice room's shared whiteboard: every item
/// (image or text) can be dragged, resized, and — for images — rotated, all
/// stored as fractions of the canvas' own size (see WhiteboardItem's doc
/// comment) so the same layout renders correctly at any size this widget is
/// given. Used both inline (the stage card's compact preview) and in the
/// full-screen expanded view (see voice_room_detail_screen.dart) — the same
/// widget either way, just at a different absolute size.
///
/// Non-editors (`canEdit: false`) get a plain read-only render — no
/// gesture handling at all, matching firestore.rules' restriction that only
/// the room's host/moderator may actually write to the board.
class WhiteboardCanvas extends StatefulWidget {
  final List<WhiteboardItem> items;
  final bool canEdit;

  /// Called once when a move or resize gesture ends, with the item's fully
  /// updated transform — never called mid-drag (the canvas renders the
  /// live position itself while dragging; see [_WhiteboardCanvasState]).
  final ValueChanged<WhiteboardItem> onTransformEnd;

  /// Called when the selected item's "⋮" handle is tapped — the caller
  /// opens whatever style/z-order/delete sheet is appropriate for that
  /// item's type (see voice_room_detail_screen.dart's `_openItemOptions`).
  final ValueChanged<WhiteboardItem> onOpenOptions;

  /// Called when the selected item's "×" handle is tapped — a quick delete
  /// without opening the options sheet, same affordance the old fixed-size
  /// tiles had.
  final ValueChanged<WhiteboardItem> onQuickDelete;

  const WhiteboardCanvas({
    super.key,
    required this.items,
    required this.canEdit,
    required this.onTransformEnd,
    required this.onOpenOptions,
    required this.onQuickDelete,
  });

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  String? _selectedId;

  // Live, uncommitted transform while a drag/resize is in progress — keyed
  // by item id, cleared (and reported via widget.onTransformEnd) the
  // moment the gesture ends. Firestore's own client-side optimistic cache
  // means the "real" value round-trips back in essentially the same frame
  // for the person dragging, so there's no visible snap-back once this is
  // cleared.
  final Map<String, WhiteboardItem> _liveOverrides = {};

  // Total pointer movement for the gesture currently in progress — lets a
  // near-stationary drag (i.e. a tap) just select the item instead of
  // committing a no-op move.
  Offset _dragAccum = Offset.zero;

  static const double _minBoxFraction = 0.08;
  static const double _tapSlop = 4;

  // Keeps every item's edge a little short of the canvas' own edge, in
  // pixels — the quick-delete/options/resize handles anchor just outside
  // an item's corners (see _buildItem), and the canvas is clipped to its
  // rounded-rect bounds by its parent (see voice_room_detail_screen.dart);
  // without this margin, an item dragged flush against the edge would push
  // its own handles half outside that clip, making them partly invisible
  // and partly untappable.
  static const double _edgeMarginPx = 14;

  WhiteboardItem _effective(WhiteboardItem item) => _liveOverrides[item.id] ?? item;

  @override
  void didUpdateWidget(covariant WhiteboardCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drop any live override for an item someone else deleted mid-drag.
    _liveOverrides.removeWhere((id, _) => !widget.items.any((i) => i.id == id));
    if (_selectedId != null && !widget.items.any((i) => i.id == _selectedId)) {
      _selectedId = null;
    }
  }

  void _onBodyPanStart(WhiteboardItem item) {
    _dragAccum = Offset.zero;
    setState(() {
      _selectedId = item.id;
      _liveOverrides[item.id] = item;
    });
  }

  void _onBodyPanUpdate(WhiteboardItem item, DragUpdateDetails details, double canvasW, double canvasH) {
    _dragAccum += details.delta;
    final current = _effective(item);
    final marginX = _edgeMarginPx / canvasW;
    final marginY = _edgeMarginPx / canvasH;
    // math.max guards against an oversized item (wider/taller than the
    // canvas minus both margins) making the clamp's own bounds invalid —
    // falls back to pinning against the near edge only, rather than
    // reserving a margin on both sides for something that can't fit.
    final double newX = (current.x + details.delta.dx / canvasW)
        .clamp(marginX, math.max(marginX, 1.0 - current.width - marginX));
    final double newY = (current.y + details.delta.dy / canvasH)
        .clamp(marginY, math.max(marginY, 1.0 - current.height - marginY));
    setState(() => _liveOverrides[item.id] = current.copyWith(x: newX, y: newY));
  }

  void _onBodyPanEnd(WhiteboardItem item) {
    final moved = _dragAccum.distance > _tapSlop;
    final finalItem = _effective(item);
    setState(() {
      _liveOverrides.remove(item.id);
      _selectedId = item.id;
    });
    if (moved) widget.onTransformEnd(finalItem);
  }

  void _onResizePanStart(WhiteboardItem item) {
    setState(() => _liveOverrides[item.id] = item);
  }

  void _onResizePanUpdate(WhiteboardItem item, DragUpdateDetails details, double canvasW, double canvasH) {
    final current = _effective(item);
    // Same edge margin as moving (see _edgeMarginPx's doc comment) — this
    // handle is anchored just outside the item's own bottom-right corner,
    // so the box it's resizing needs to stop just short of the canvas
    // edge too, or the handle itself ends up partly clipped.
    final marginX = _edgeMarginPx / canvasW;
    final marginY = _edgeMarginPx / canvasH;
    final maxWidth = math.max(_minBoxFraction, 1.0 - current.x - marginX);
    final maxHeightBound = math.max(_minBoxFraction, 1.0 - current.y - marginY);

    var newWidth = (current.width + details.delta.dx / canvasW).clamp(_minBoxFraction, maxWidth);
    double newHeight;

    final ratio = item.aspectRatio;
    if (item.isImage && ratio != null && ratio > 0) {
      // Locked to the source image's own proportions — dragging only ever
      // changes width; height (and, if that would run off the bottom edge,
      // width again) follows to keep the box's true visual aspect ratio,
      // not just its stored width/height fractions (see
      // WhiteboardGeometry's doc comment for why those two only match when
      // every canvas this renders in shares the same aspect ratio).
      newHeight = newWidth * WhiteboardGeometry.aspectRatio / ratio;
      if (newHeight > maxHeightBound) {
        newHeight = maxHeightBound;
        newWidth = (newHeight * ratio / WhiteboardGeometry.aspectRatio).clamp(_minBoxFraction, maxWidth);
      }
      if (newHeight < _minBoxFraction) newHeight = _minBoxFraction;
    } else {
      newHeight = (current.height + details.delta.dy / canvasH).clamp(_minBoxFraction, maxHeightBound);
    }

    // For text, resizing the box IS resizing the text — the font grows or
    // shrinks with the box (by the box's own area change, so it tracks
    // however the user actually drags: wider, taller, or both) rather than
    // leaving a fixed-size line of text stranded in a corner of a bigger
    // box. Area-based (not just width or just height) so a diagonal drag
    // feels proportionate either way.
    double? newFontSize;
    if (item.isText) {
      final oldAreaPx = current.width * canvasW * current.height * canvasH;
      final newAreaPx = newWidth * canvasW * newHeight * canvasH;
      if (oldAreaPx > 0) {
        final scale = math.sqrt(newAreaPx / oldAreaPx);
        newFontSize = (current.fontSize * scale).clamp(10.0, 96.0);
      }
    }

    setState(() {
      _liveOverrides[item.id] = current.copyWith(width: newWidth, height: newHeight, fontSize: newFontSize);
    });
  }

  void _onResizePanEnd(WhiteboardItem item) {
    final finalItem = _effective(item);
    setState(() => _liveOverrides.remove(item.id));
    widget.onTransformEnd(finalItem);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.items]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasW = constraints.maxWidth;
        final canvasH = constraints.maxHeight;

        if (sorted.isEmpty) {
          if (!widget.canEdit) return const SizedBox.shrink();
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Tap "Add images" or "Type text" to start the board',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Tapping empty canvas space deselects whatever's selected.
            if (widget.canEdit)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _selectedId = null),
                ),
              ),
            for (final raw in sorted) ..._buildItem(raw, canvasW, canvasH),
          ],
        );
      },
    );
  }

  List<Widget> _buildItem(WhiteboardItem raw, double canvasW, double canvasH) {
    final item = _effective(raw);
    final left = item.x * canvasW;
    final top = item.y * canvasH;
    final width = item.width * canvasW;
    final height = item.height * canvasH;
    final selected = widget.canEdit && _selectedId == raw.id;
    final radius = item.isImage ? 8.0 : 10.0;

    Widget content = item.isImage ? _buildImage(item, width, height, radius) : _buildText(item, radius);
    if (item.isImage && item.rotation != 0) {
      content = Transform.rotate(angle: item.rotation * math.pi / 180, child: content);
    }

    final body = Positioned(
      key: ValueKey('wb_body_${raw.id}'),
      left: left,
      top: top,
      width: width,
      height: height,
      child: widget.canEdit
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _onBodyPanStart(raw),
              onPanUpdate: (d) => _onBodyPanUpdate(raw, d, canvasW, canvasH),
              onPanEnd: (_) => _onBodyPanEnd(raw),
              child: Container(
                decoration: selected
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(radius + 2),
                        border: Border.all(color: const Color(0xFF7B68F4), width: 2),
                      )
                    : null,
                padding: selected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                child: content,
              ),
            )
          : content,
    );

    if (!selected) return [body];

    return [
      body,
      Positioned(
        key: ValueKey('wb_del_${raw.id}'),
        left: left - 10,
        top: top - 10,
        child: _HandleButton(icon: Icons.close_rounded, onTap: () => widget.onQuickDelete(raw)),
      ),
      Positioned(
        key: ValueKey('wb_opt_${raw.id}'),
        left: left + width - 10,
        top: top - 10,
        child: _HandleButton(icon: Icons.tune_rounded, onTap: () => widget.onOpenOptions(raw)),
      ),
      Positioned(
        key: ValueKey('wb_resize_${raw.id}'),
        left: left + width - 11,
        top: top + height - 11,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _onResizePanStart(raw),
          onPanUpdate: (d) => _onResizePanUpdate(raw, d, canvasW, canvasH),
          onPanEnd: (_) => _onResizePanEnd(raw),
          child: const _HandleButton(icon: Icons.open_in_full_rounded, filled: true),
        ),
      ),
    ];
  }

  Widget _buildImage(WhiteboardItem item, double width, double height, double radius) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        item.imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: Colors.white12,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
        ),
      ),
    );
  }

  Widget _buildText(WhiteboardItem item, double radius) {
    final align = switch (item.textAlign) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    Color color;
    try {
      color = Color(int.parse('0x${item.colorHex}'));
    } catch (_) {
      color = Colors.white;
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(radius),
      ),
      // No `alignment` here (deliberately — see below): it looked like the
      // right way to pin content to the top-left, but Container reacts to
      // a non-null `alignment` by giving its child LOOSE constraints
      // (shrink-wrap to content) instead of the box's full size. That
      // silently broke center/right alignment — the Text was always
      // already exactly as wide as its own content, so `textAlign` had no
      // extra room to actually do anything. The SizedBox below now forces
      // full width explicitly instead, and top-left is just the natural
      // resting position for non-centered content, so nothing else here
      // needs to change to keep that look.
      //
      // A resized-smaller box scrolls its overflowing text rather than
      // clipping or overflow-painting past its own bounds — keeps the
      // board tidy ("fits properly within the whiteboard") without losing
      // any of what was typed.
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            item.text,
            textAlign: align,
            style: TextStyle(
              fontSize: item.fontSize,
              fontWeight: item.bold ? FontWeight.w800 : FontWeight.w500,
              color: color,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

class _HandleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  const _HandleButton({required this.icon, this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF7B68F4) : Colors.black87,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Icon(icon, size: 12, color: Colors.white),
      ),
    );
  }
}
