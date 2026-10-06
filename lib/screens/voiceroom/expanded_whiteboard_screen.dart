import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/whiteboard_item.dart';
import '../../services/whiteboard_service.dart';
import '../../widgets/whiteboard_canvas.dart';

/// The stage card's whiteboard, full-screen — reachable via the small
/// expand icon on the inline card (see VoiceRoomDetailScreen). Same
/// WhiteboardCanvas, same live Firestore stream, with support for smooth
/// pinch-to-zoom, dragging, and Portrait / Landscape orientation switching.
class ExpandedWhiteboardScreen extends StatefulWidget {
  final String roomId;
  final bool canEdit;
  final Stream<List<WhiteboardItem>> itemsStream;

  /// The caller's already-cached item list (from VoiceRoomDetailScreen's
  /// `_whiteboardItems`) — used as the StreamBuilder's `initialData` so
  /// the canvas renders immediately on open rather than showing a blank
  /// board while waiting for the first Firestore event.
  final List<WhiteboardItem> initialItems;

  final ValueChanged<WhiteboardItem> onTransformEnd;
  final ValueChanged<WhiteboardItem> onOpenOptions;
  final ValueChanged<WhiteboardItem> onQuickDelete;
  final VoidCallback? onAddImage;

  const ExpandedWhiteboardScreen({
    super.key,
    required this.roomId,
    required this.canEdit,
    required this.itemsStream,
    required this.initialItems,
    required this.onTransformEnd,
    required this.onOpenOptions,
    required this.onQuickDelete,
    this.onAddImage,
  });

  @override
  State<ExpandedWhiteboardScreen> createState() => _ExpandedWhiteboardScreenState();
}

class _ExpandedWhiteboardScreenState extends State<ExpandedWhiteboardScreen> {
  late bool _isLandscape;

  @override
  void initState() {
    super.initState();
    // Default to portrait if the primary image on the board is portrait / tall (< 0.95),
    // otherwise default to standard landscape.
    final firstImage = widget.initialItems.where((i) => i.isImage).firstOrNull;
    if (firstImage != null && firstImage.aspectRatio != null && firstImage.aspectRatio! < 0.95) {
      _isLandscape = false;
    } else {
      _isLandscape = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B1B3A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B3A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.canEdit ? 'Whiteboard — drag to rearrange' : 'Whiteboard',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5),
        ),
        actions: [
          if (widget.canEdit && widget.onAddImage != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onAddImage!();
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B68F4).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF7B68F4).withValues(alpha: 0.7),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_rounded,
                          size: 16,
                          color: Color(0xFF7B68F4),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Add image',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isLandscape = !_isLandscape);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF7B68F4).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLandscape ? Icons.crop_landscape_rounded : Icons.crop_portrait_rounded,
                        size: 16,
                        color: const Color(0xFF7B68F4),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isLandscape ? 'Landscape' : 'Portrait',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: AspectRatio(
              aspectRatio: _isLandscape ? WhiteboardGeometry.aspectRatio : (9 / 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: StreamBuilder<List<WhiteboardItem>>(
                  stream: widget.itemsStream,
                  initialData: widget.initialItems,
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? const <WhiteboardItem>[];
                    return WhiteboardCanvas(
                      items: items,
                      canEdit: widget.canEdit,
                      onTransformEnd: widget.onTransformEnd,
                      onOpenOptions: widget.onOpenOptions,
                      onQuickDelete: widget.onQuickDelete,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
