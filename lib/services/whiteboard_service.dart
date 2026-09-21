import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/whiteboard_item.dart';
import 'auth_service.dart';

/// Firestore access for `voiceRooms/{roomId}/whiteboard/{itemId}` — the
/// room's shared free-position image/text canvas (the stage card in
/// VoiceRoomDetailScreen, and its full-screen expanded view — see
/// lib/widgets/whiteboard_canvas.dart). Adding, editing, transforming
/// (move/resize/rotate/reorder), and removing items is restricted to the
/// room's host/moderator, both client-side (see the `canModerate` guard on
/// every write below) and in firestore.rules — everyone else can only view
/// via [streamItems].
class WhiteboardService {
  static CollectionReference<Map<String, dynamic>> _items(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).collection('whiteboard');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// A freshly-added item's default box, in canvas fractions (0..1) —
  /// small enough that several fit on a phone-sized board without a resize.
  static const double defaultWidth = 0.32;
  static const double defaultHeight = 0.22;
  static const double _minPlacement = 0.04;
  static const double _placementStep = 0.055;

  /// Oldest first — the initial fetch order; on-screen stacking is actually
  /// driven by each item's own `zIndex` (see WhiteboardCanvas), not this.
  static Stream<List<WhiteboardItem>> streamItems(String roomId) {
    if (roomId.isEmpty) return Stream.value(const []);
    return _items(roomId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(WhiteboardItem.fromFirestore).toList())
        .handleError((e) {
          debugPrint('WhiteboardService.streamItems failed (showing nothing): $e');
          return <WhiteboardItem>[];
        });
  }

  /// Picks a starting box for a new item that doesn't land on top of
  /// anything already on the board, when there's room for that — a simple
  /// diagonal cascade, skipping any slot that would overlap an existing
  /// item. Once the board is too full to avoid overlap entirely, it still
  /// cascades (so new items don't all pile up in exactly the same spot)
  /// rather than giving up and stacking blindly at the origin.
  static ({double x, double y}) _nextPlacement(
    List<WhiteboardItem> existing, {
    required double width,
    required double height,
  }) {
    const columns = 6;
    for (var attempt = 0; attempt < 30; attempt++) {
      final x = (_minPlacement + (attempt % columns) * _placementStep).clamp(0.0, 1.0 - width);
      final y = (_minPlacement + (attempt ~/ columns) * _placementStep).clamp(0.0, 1.0 - height);
      final overlapsExisting = existing.any(
        (item) => _overlaps(x, y, width, height, item.x, item.y, item.width, item.height),
      );
      if (!overlapsExisting) return (x: x, y: y);
    }
    final n = existing.length;
    return (
      x: (_minPlacement + (n % columns) * _placementStep).clamp(0.0, 1.0 - width),
      y: (_minPlacement + (n ~/ columns) * _placementStep).clamp(0.0, 1.0 - height),
    );
  }

  static bool _overlaps(
    double ax,
    double ay,
    double aw,
    double ah,
    double bx,
    double by,
    double bw,
    double bh,
  ) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
  }

  static int _nextZIndex(List<WhiteboardItem> existing) {
    if (existing.isEmpty) return 0;
    return existing.map((e) => e.zIndex).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// [aspectRatio] is the picked image's natural width/height — stored so
  /// WhiteboardCanvas's resize handle can keep the box in proportion.
  /// [existingItems] is the board's current items (the caller already has
  /// this in hand from its own live subscription — see
  /// VoiceRoomDetailScreen._whiteboardItems), used only to pick a
  /// non-overlapping starting position and a stacking order above
  /// everything already placed.
  static Future<void> addImage({
    required String roomId,
    required String imageUrl,
    required double aspectRatio,
    List<WhiteboardItem> existingItems = const [],
  }) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    if (uid == null || user == null || roomId.isEmpty || imageUrl.isEmpty) return;

    // Keep the box's on-screen aspect ratio matching the source image —
    // see WhiteboardGeometry's doc comment for why this width-fraction/
    // height-fraction pair reproduces the same visual shape on any device
    // (the canvas itself is always rendered at that same fixed ratio, just
    // at different absolute sizes).
    final height = (defaultWidth * WhiteboardGeometry.aspectRatio / aspectRatio).clamp(0.08, 0.9);
    final placement = _nextPlacement(existingItems, width: defaultWidth, height: height);

    await _items(roomId).add({
      'type': 'image',
      'imageUrl': imageUrl,
      'addedBy': uid,
      'addedByName': user.name,
      'createdAt': FieldValue.serverTimestamp(),
      'x': placement.x,
      'y': placement.y,
      'width': defaultWidth,
      'height': height,
      'rotation': 0,
      'zIndex': _nextZIndex(existingItems),
      'aspectRatio': aspectRatio,
    });
  }

  static Future<void> addText({
    required String roomId,
    required String text,
    List<WhiteboardItem> existingItems = const [],
    double fontSize = 16,
    String colorHex = 'FFFFFFFF',
    bool bold = false,
    String textAlign = 'left',
  }) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    final trimmed = text.trim();
    if (uid == null || user == null || roomId.isEmpty || trimmed.isEmpty) return;

    final placement = _nextPlacement(existingItems, width: defaultWidth, height: defaultHeight);

    await _items(roomId).add({
      'type': 'text',
      'text': trimmed,
      'addedBy': uid,
      'addedByName': user.name,
      'createdAt': FieldValue.serverTimestamp(),
      'x': placement.x,
      'y': placement.y,
      'width': defaultWidth,
      'height': defaultHeight,
      'rotation': 0,
      'zIndex': _nextZIndex(existingItems),
      'fontSize': fontSize,
      'colorHex': colorHex,
      'bold': bold,
      'textAlign': textAlign,
    });
  }

  /// Replaces a text item's content and style together in one write — the
  /// text composer sheet's "Save" on an existing item (see
  /// voice_room_detail_screen.dart's `_openWhiteboardItemOptions`).
  static Future<void> saveText({
    required String roomId,
    required String itemId,
    required String text,
    required double fontSize,
    required String colorHex,
    required bool bold,
    required String textAlign,
  }) async {
    final trimmed = text.trim();
    if (roomId.isEmpty || itemId.isEmpty || trimmed.isEmpty) return;
    await _items(roomId).doc(itemId).update({
      'text': trimmed,
      'fontSize': fontSize,
      'colorHex': colorHex,
      'bold': bold,
      'textAlign': textAlign,
    });
  }

  /// Commits a move/resize/rotate — called once when the user releases a
  /// drag or resize handle (see WhiteboardCanvas), never per-frame while
  /// dragging: the canvas already renders the live position locally as the
  /// gesture is in progress, so writing here on every pointer move would
  /// just spam Firestore for a visual that's already showing correctly.
  /// [fontSize] is only meaningful for a text item being resized — the
  /// canvas scales the text along with its box (see WhiteboardCanvas's
  /// resize handler) rather than leaving the font a fixed size inside a
  /// bigger or smaller box.
  static Future<void> updateTransform({
    required String roomId,
    required String itemId,
    required double x,
    required double y,
    required double width,
    required double height,
    double? rotation,
    double? fontSize,
  }) async {
    if (roomId.isEmpty || itemId.isEmpty) return;
    await _items(roomId).doc(itemId).update({
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': ?rotation,
      'fontSize': ?fontSize,
    });
  }

  /// Raises [itemId] above every other item currently on the board.
  static Future<void> bringToFront({
    required String roomId,
    required String itemId,
    required List<WhiteboardItem> existingItems,
  }) async {
    if (roomId.isEmpty || itemId.isEmpty) return;
    await _items(roomId).doc(itemId).update({'zIndex': _nextZIndex(existingItems)});
  }

  /// Drops [itemId] below every other item currently on the board.
  static Future<void> sendToBack({
    required String roomId,
    required String itemId,
    required List<WhiteboardItem> existingItems,
  }) async {
    if (roomId.isEmpty || itemId.isEmpty) return;
    final lowest = existingItems.isEmpty
        ? 0
        : existingItems.map((e) => e.zIndex).reduce((a, b) => a < b ? a : b) - 1;
    await _items(roomId).doc(itemId).update({'zIndex': lowest});
  }

  static Future<void> removeItem({required String roomId, required String itemId}) async {
    if (roomId.isEmpty || itemId.isEmpty) return;
    await _items(roomId).doc(itemId).delete();
  }
}

/// Shared "shape" constant for the whiteboard canvas — see
/// lib/widgets/whiteboard_canvas.dart's WhiteboardCanvas.aspectRatio for why
/// this has to stay identical everywhere the board renders (the inline
/// stage card AND the full-screen expanded view) for an image's stored
/// width/height fractions to reproduce its real aspect ratio consistently.
class WhiteboardGeometry {
  static const double aspectRatio = 1.8;
}
