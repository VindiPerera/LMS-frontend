import 'package:flutter/material.dart';

import '../../models/whiteboard_item.dart';
import '../../services/whiteboard_service.dart';
import '../../widgets/whiteboard_canvas.dart';

/// The stage card's whiteboard, full-screen — reachable via the small
/// expand icon on the inline card (see VoiceRoomDetailScreen). Same
/// WhiteboardCanvas, same live Firestore stream, just given a lot more
/// room to work with than the card's small preview allows — most useful
/// for precisely dragging/resizing items on a phone. Adding brand-new
/// items still happens from the card's own "Add images"/"Type text"
/// toolbar; this screen is for arranging what's already there.
class ExpandedWhiteboardScreen extends StatelessWidget {
  final String roomId;
  final bool canEdit;
  final Stream<List<WhiteboardItem>> itemsStream;

  /// The caller's already-cached item list (from VoiceRoomDetailScreen's
  /// `_whiteboardItems`) — used as the StreamBuilder's `initialData` so
  /// the canvas renders immediately on open rather than showing a blank
  /// board while waiting for the first Firestore event. Broadcast streams
  /// (asBroadcastStream) don't replay their last value to new subscribers,
  /// so without this there would be a visible blank flash every time.
  final List<WhiteboardItem> initialItems;

  final ValueChanged<WhiteboardItem> onTransformEnd;
  final ValueChanged<WhiteboardItem> onOpenOptions;
  final ValueChanged<WhiteboardItem> onQuickDelete;

  const ExpandedWhiteboardScreen({
    super.key,
    required this.roomId,
    required this.canEdit,
    required this.itemsStream,
    required this.initialItems,
    required this.onTransformEnd,
    required this.onOpenOptions,
    required this.onQuickDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B1B3A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B3A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          canEdit ? 'Whiteboard — drag to rearrange' : 'Whiteboard',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: AspectRatio(
              // Same shape as the inline card — see WhiteboardGeometry's doc
              // comment for why every render of this board has to agree on
              // one aspect ratio for an image's proportions to stay correct.
              aspectRatio: WhiteboardGeometry.aspectRatio,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: StreamBuilder<List<WhiteboardItem>>(
                  stream: itemsStream,
                  // Seed with the already-known items so the canvas shows
                  // content immediately on open — see initialItems doc comment.
                  initialData: initialItems,
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? const <WhiteboardItem>[];
                    return WhiteboardCanvas(
                      items: items,
                      canEdit: canEdit,
                      onTransformEnd: onTransformEnd,
                      onOpenOptions: onOpenOptions,
                      onQuickDelete: onQuickDelete,
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
