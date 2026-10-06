import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/whiteboard_item.dart';
import '../models/whiteboard_library_data.dart';
import '../models/whiteboard_library_item.dart';

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

  // The item's box exactly as it was the moment the current body gesture
  // (_onBodyScaleStart) began — the fixed baseline a pinch's *cumulative*
  // `details.scale` is applied against. Unlike a plain drag delta, scale
  // isn't incremental frame-to-frame, so resizing from the live, already-
  // resized box on every update (the way a delta-based drag correctly does)
  // would compound and blow the box up or shrink it far faster than the
  // fingers actually moved. Null outside of an active body gesture.
  WhiteboardItem? _scaleStartItem;

  static const double _minBoxFraction = 0.08;
  static const double _tapSlop = 4;

  // Every handle (delete/options/resize) is drawn centered on its own
  // anchor point (an item corner) at [_handleVisualSize] across, but sits
  // inside a [_handleTouchSize] hit-test region — a full Material/HIG-sized
  // touch target (44dp) — so it stays easy to grab on any screen density
  // without the visible circle itself looking oversized. See _HandleButton.
  static const double _handleVisualSize = 26;
  static const double _handleTouchSize = 44;

  // Keeps every item's edge a little short of the canvas' own edge, in
  // pixels — the quick-delete/options/resize handles anchor just outside an
  // item's corners (see _buildItem), and the canvas is clipped to its
  // rounded-rect bounds by its parent (see voice_room_detail_screen.dart) —
  // a hard clip in Flutter cuts off hit-testing along with painting, not
  // just what's drawn. This margin has to clear each handle's full
  // [_handleTouchSize] footprint (not just its visible circle), or a handle
  // dragged toward the edge would have its touch target itself clipped —
  // silently shrinking how much of it actually responds to touch — well
  // before any clipping became visible.
  static const double _edgeMarginPx = _handleTouchSize / 2 + 4;

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

  // A dedicated tap handler, separate from the drag/pinch recognizer below
  // — a Pan/Scale recognizer only ever calls its onStart once the pointer
  // has moved past its own internal slop threshold, so a genuinely
  // still tap-and-release (no perceptible movement at all) could otherwise
  // land on an item and select nothing. Flutter's gesture arena runs a Tap
  // and a Scale recognizer on the same GestureDetector safely side by
  // side — whichever the touch actually turns out to be (a still tap vs.
  // real movement) wins on its own, so this never double-fires alongside
  // _onBodyScaleStart below for one continuous touch.
  void _onBodyTap(WhiteboardItem item) {
    if (_selectedId == item.id) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedId = item.id);
  }

  // The body drag uses Scale (not Pan) so a single finger keeps moving the
  // item exactly as a plain drag always has (details.scale stays 1.0 for a
  // single pointer, so the resize branch below is simply never entered),
  // while a second finger touching down mid-gesture is recognized as a
  // pinch instead of being misread as a sudden, erratic jump in a
  // single-pointer Pan recognizer's own delta — Flutter's own recommended
  // pattern for a widget that needs to support drag AND pinch together.
  // This is also the resize handle's own corner-drag path (below) getting
  // priority in its small hit region, and body pinch/drag priority
  // everywhere else — see _buildItem's Stack ordering.
  void _onBodyScaleStart(WhiteboardItem item) {
    _dragAccum = Offset.zero;
    final current = _effective(item);
    _scaleStartItem = current;
    if (_selectedId != item.id) HapticFeedback.selectionClick();
    setState(() {
      _selectedId = item.id;
      _liveOverrides[item.id] = current;
    });
  }

  void _onBodyScaleUpdate(WhiteboardItem item, ScaleUpdateDetails details, double canvasW, double canvasH) {
    _dragAccum += details.focalPointDelta;
    final current = _effective(item);
    final start = _scaleStartItem ?? current;
    final marginX = _edgeMarginPx / canvasW;
    final marginY = _edgeMarginPx / canvasH;
    final canvasRatio = canvasW / canvasH;

    var newWidth = current.width;
    var newHeight = current.height;
    var newX = current.x;
    var newY = current.y;
    double? newFontSize;

    if (details.pointerCount > 1) {
      // TWO-FINGER PINCH TO ZOOM:
      // Symmetrically scales around the pinch center, preserving the item's
      // true aspect ratio without jumping or snapping.
      final scale = details.scale;
      final targetW = (start.width * scale).clamp(_minBoxFraction, 3.0);
      double targetH;

      final ratio = item.aspectRatio;
      if (item.isImage && ratio != null && ratio > 0) {
        targetH = targetW * canvasRatio / ratio;
      } else {
        targetH = (start.height * scale).clamp(_minBoxFraction, 3.0);
      }

      final deltaW = targetW - current.width;
      final deltaH = targetH - current.height;

      newWidth = targetW;
      newHeight = targetH;
      newX = current.x - (deltaW / 2) + (details.focalPointDelta.dx / canvasW);
      newY = current.y - (deltaH / 2) + (details.focalPointDelta.dy / canvasH);

      if (item.isText) {
        final oldAreaPx = start.width * canvasW * start.height * canvasH;
        final newAreaPx = newWidth * canvasW * newHeight * canvasH;
        if (oldAreaPx > 0) {
          final fontScale = math.sqrt(newAreaPx / oldAreaPx);
          newFontSize = (start.fontSize * fontScale).clamp(10.0, 96.0);
        }
      }
    } else {
      // ONE-FINGER DRAG TO MOVE:
      newX = current.x + (details.focalPointDelta.dx / canvasW);
      newY = current.y + (details.focalPointDelta.dy / canvasH);
    }

    // Boundary clamp: keeps the item within usable whiteboard area
    if (newWidth <= 1.0 - 2 * marginX) {
      newX = newX.clamp(marginX, math.max(marginX, 1.0 - newWidth - marginX));
    } else {
      newX = newX.clamp(1.0 - newWidth - marginX, marginX);
    }

    if (newHeight <= 1.0 - 2 * marginY) {
      newY = newY.clamp(marginY, math.max(marginY, 1.0 - newHeight - marginY));
    } else {
      newY = newY.clamp(1.0 - newHeight - marginY, marginY);
    }

    setState(() {
      _liveOverrides[item.id] = current.copyWith(
        x: newX,
        y: newY,
        width: newWidth,
        height: newHeight,
        fontSize: newFontSize,
      );
    });
  }

  void _onBodyScaleEnd(WhiteboardItem item) {
    final moved = _dragAccum.distance > _tapSlop;
    final finalItem = _effective(item);
    _scaleStartItem = null;
    setState(() {
      _liveOverrides.remove(item.id);
      _selectedId = item.id;
    });
    if (moved) widget.onTransformEnd(finalItem);
  }

  void _onResizePanStart(WhiteboardItem item) {
    HapticFeedback.selectionClick();
    setState(() => _liveOverrides[item.id] = item);
  }

  void _onResizePanUpdate(WhiteboardItem item, DragUpdateDetails details, double canvasW, double canvasH) {
    final current = _effective(item);
    final marginX = _edgeMarginPx / canvasW;
    final marginY = _edgeMarginPx / canvasH;
    final resized = _resizeWithinBounds(
      item: item,
      base: current,
      targetWidth: current.width + details.delta.dx / canvasW,
      targetHeight: current.height + details.delta.dy / canvasH,
      canvasW: canvasW,
      canvasH: canvasH,
      marginX: marginX,
      marginY: marginY,
    );
    setState(() {
      _liveOverrides[item.id] =
          current.copyWith(width: resized.width, height: resized.height, fontSize: resized.fontSize);
    });
  }

  void _onResizePanEnd(WhiteboardItem item) {
    final finalItem = _effective(item);
    setState(() => _liveOverrides.remove(item.id));
    widget.onTransformEnd(finalItem);
  }

  // Shared by the corner resize handle's single-finger drag (delta-based,
  // [base] is the live/current box) and the body's two-finger pinch
  // (scale-based, [base] is the box captured when the pinch started) — one
  // place for the boundary clamp, aspect-ratio lock and text-area-based
  // font scaling, so the two gestures can never quietly drift into
  // resizing differently from one another.
  ({double width, double height, double? fontSize}) _resizeWithinBounds({
    required WhiteboardItem item,
    required WhiteboardItem base,
    required double targetWidth,
    required double targetHeight,
    required double canvasW,
    required double canvasH,
    required double marginX,
    required double marginY,
  }) {
    // Same edge margin as moving (see _edgeMarginPx's doc comment) — the
    // box being resized needs to stop just short of the canvas edge, or its
    // own resize handle ends up partly clipped.
    final maxWidth = math.max(_minBoxFraction, 1.0 - base.x - marginX);
    final maxHeightBound = math.max(_minBoxFraction, 1.0 - base.y - marginY);

    var newWidth = targetWidth.clamp(_minBoxFraction, maxWidth);
    double newHeight;

    final ratio = item.aspectRatio;
    final canvasRatio = canvasW / canvasH;
    if (item.isImage && ratio != null && ratio > 0) {
      // Locked to the source image's own proportions — width drives the
      // box; height follows to keep the box's true visual aspect ratio.
      newHeight = newWidth * canvasRatio / ratio;
      if (newHeight > maxHeightBound) {
        newHeight = maxHeightBound;
        newWidth = (newHeight * ratio / canvasRatio).clamp(_minBoxFraction, maxWidth);
      }
      if (newHeight < _minBoxFraction) newHeight = _minBoxFraction;
    } else {
      newHeight = targetHeight.clamp(_minBoxFraction, maxHeightBound);
    }

    // For text, resizing the box IS resizing the text — the font grows or
    // shrinks with the box (by the box's own area change relative to
    // [base], so it tracks however the user actually gestures: wider,
    // taller, or both) rather than leaving a fixed-size line of text
    // stranded in a corner of a bigger box. Area-based so a diagonal drag
    // or an off-axis pinch both feel proportionate.
    double? newFontSize;
    if (item.isText) {
      final oldAreaPx = base.width * canvasW * base.height * canvasH;
      final newAreaPx = newWidth * canvasW * newHeight * canvasH;
      if (oldAreaPx > 0) {
        final scale = math.sqrt(newAreaPx / oldAreaPx);
        newFontSize = (base.fontSize * scale).clamp(10.0, 96.0);
      }
    }

    return (width: newWidth, height: newHeight, fontSize: newFontSize);
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
                'Tap "Add images" or "Type topic" to start the board',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Tapping empty canvas space deselects; two-finger pinch on the canvas
            // zooms the active image smoothly even if fingers touch outside its box.
            if (widget.canEdit)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _selectedId = null),
                  onScaleStart: (_) {
                    final target = sorted.where((i) => i.id == _selectedId).firstOrNull ??
                        (sorted.length == 1 && sorted.first.isImage ? sorted.first : null);
                    if (target != null) _onBodyScaleStart(target);
                  },
                  onScaleUpdate: (d) {
                    final target = sorted.where((i) => i.id == _selectedId).firstOrNull ??
                        (sorted.length == 1 && sorted.first.isImage ? sorted.first : null);
                    if (target != null && d.pointerCount > 1) {
                      _onBodyScaleUpdate(target, d, canvasW, canvasH);
                    }
                  },
                  onScaleEnd: (_) {
                    final target = sorted.where((i) => i.id == _selectedId).firstOrNull ??
                        (sorted.length == 1 && sorted.first.isImage ? sorted.first : null);
                    if (target != null) _onBodyScaleEnd(target);
                  },
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
              onTap: () => _onBodyTap(raw),
              onScaleStart: (_) => _onBodyScaleStart(raw),
              onScaleUpdate: (d) => _onBodyScaleUpdate(raw, d, canvasW, canvasH),
              onScaleEnd: (_) => _onBodyScaleEnd(raw),
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

    // Each handle below is anchored at an item corner (delete/options at the
    // top corners, resize at the bottom-right) but occupies a full
    // _handleTouchSize square centered on that point — only the inner
    // _handleVisualSize circle is actually drawn, via _HandleButton's own
    // Center, so the tap/drag target is far more forgiving than what's
    // visible without the handles looking oversized. See _edgeMarginPx's
    // doc comment for why the item itself never drags close enough to the
    // canvas edge to clip any of this.
    const half = _handleTouchSize / 2;

    return [
      body,
      Positioned(
        key: ValueKey('wb_del_${raw.id}'),
        left: left - half,
        top: top - half,
        width: _handleTouchSize,
        height: _handleTouchSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onQuickDelete(raw),
          child: const Center(
            child: _HandleButton(icon: Icons.close_rounded, size: _handleVisualSize),
          ),
        ),
      ),
      Positioned(
        key: ValueKey('wb_opt_${raw.id}'),
        left: left + width - half,
        top: top - half,
        width: _handleTouchSize,
        height: _handleTouchSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onOpenOptions(raw),
          // A text item's "options" IS its editor (wording/style/z-order/
          // delete — see voice_room_detail_screen.dart's
          // _openWhiteboardItemOptions), so this reads as "Edit" for text;
          // an image's sheet is genuinely a different set of actions
          // (rotate/z-order/delete, no wording to edit), so it keeps the
          // generic tune icon.
          child: Center(
            child: _HandleButton(
              icon: item.isText ? Icons.edit_rounded : Icons.tune_rounded,
              size: _handleVisualSize,
            ),
          ),
        ),
      ),
      Positioned(
        key: ValueKey('wb_resize_${raw.id}'),
        left: left + width - half,
        top: top + height - half,
        width: _handleTouchSize,
        height: _handleTouchSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _onResizePanStart(raw),
          onPanUpdate: (d) => _onResizePanUpdate(raw, d, canvasW, canvasH),
          onPanEnd: (_) => _onResizePanEnd(raw),
          child: const Center(
            child: _HandleButton(icon: Icons.open_in_full_rounded, size: _handleVisualSize, filled: true),
          ),
        ),
      ),
    ];
  }

  Widget _buildImage(WhiteboardItem item, double width, double height, double radius) {
    final isAsset = item.imageUrl.startsWith('assets/');

    Widget brokenImagePlaceholder() => Container(
      color: Colors.white12,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
    );

    Widget fallbackImage() {
      final topicId = RegExp(r'topic_[a-z_]+').firstMatch(item.imageUrl)?.group(0);
      if (topicId != null) {
        final bytes = WhiteboardLibraryData.getBytes(topicId);
        if (bytes.isNotEmpty) {
          return Image.memory(bytes, width: width, height: height, fit: BoxFit.contain);
        }
        // A preset added after whiteboard_library_data.dart's embedded set
        // (see WhiteboardLibraryItem.presets) has no entry there, but still
        // ships as a real bundled asset — fall back to that instead of
        // treating every network failure as unrecoverable.
        for (final preset in WhiteboardLibraryItem.presets) {
          if (preset.id == topicId) {
            return Image.asset(
              preset.assetPath,
              width: width,
              height: height,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => brokenImagePlaceholder(),
            );
          }
        }
      }
      return brokenImagePlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        color: Colors.black.withValues(alpha: 0.15),
        child: isAsset
            ? Image.asset(
                item.imageUrl,
                width: width,
                height: height,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallbackImage(),
              )
            : Image.network(
                item.imageUrl,
                width: width,
                height: height,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallbackImage(),
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
      // Equal on every side so text never hugs (or touches) the box edge.
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(radius),
      ),
      // No `alignment` here (deliberately — see below): it looked like the
      // right way to center content, but Container reacts to a non-null
      // `alignment` by giving its child LOOSE constraints (shrink-wrap to
      // content) instead of the box's full size. That silently broke
      // center/right `textAlign` — the Text was always already exactly as
      // wide as its own content, so `textAlign` had no extra room to
      // actually do anything. The SizedBox below forces full width
      // explicitly instead, so `textAlign` keeps working regardless of how
      // this centers vertically.
      //
      // Vertical centering (both axes, by default, for a freshly-added
      // item — see WhiteboardService.defaultWidth's doc comment) is done
      // via LayoutBuilder + a ConstrainedBox(minHeight: ...) matching the
      // box's own available height: short text gets equal space above and
      // below via Center; once the text is taller than that, minHeight
      // simply stops constraining anything and the SingleChildScrollView
      // below takes over, scrolling from the top — same as before, keeping
      // the board tidy ("fits properly within the whiteboard") for a
      // resized-smaller box without losing any of what was typed.
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
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
            ),
          );
        },
      ),
    );
  }
}

/// Purely the visible circle — tap/drag handling belongs to whatever
/// GestureDetector wraps this (see _buildItem), which is sized to the
/// larger, touch-friendly hit target this sits centered inside of.
class _HandleButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool filled;
  const _HandleButton({required this.icon, required this.size, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? const Color(0xFF7B68F4) : Colors.black87,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        // A soft shadow keeps every handle readable regardless of what's
        // directly under it — a light-colored image, pale text, or the
        // board's own dark background — rather than relying on the border
        // alone for contrast.
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Icon(icon, size: size * 0.55, color: Colors.white),
    );
  }
}
