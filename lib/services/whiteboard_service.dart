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

  /// A freshly-added item's default box, in canvas fractions (0..1) — near
  /// the board's full available area (minus a small edge margin, so the
  /// selection/resize handles anchored just outside the item's corners —
  /// see WhiteboardCanvas — stay clear of the board's own rounded-rect
  /// clip), like starting a fresh "slide". Applies to both text and images
  /// alike; the user can still resize it smaller afterwards via the
  /// canvas's own resize handle if they want more than one item visible on
  /// the board at once.
  static const double defaultWidth = 0.94;
  static const double defaultHeight = 0.94;

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

  static int _nextZIndex(List<WhiteboardItem> existing) {
    if (existing.isEmpty) return 0;
    return existing.map((e) => e.zIndex).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// [aspectRatio] is the picked image's natural width/height — stored so
  /// WhiteboardCanvas's resize handle can keep the box in proportion.
  /// [existingItems] is the board's current items (the caller already has
  /// this in hand from its own live subscription — see
  /// VoiceRoomDetailScreen._whiteboardItems), used both to pick a
  /// non-overlapping starting position/stacking order among the text items
  /// staying behind, and to find any previous photo to replace.
  ///
  /// Only one photo is ever on the board at a time — a newly-added image
  /// replaces whatever image was already there (deleted in the same batch,
  /// so a viewer never sees both at once even for a frame) rather than
  /// piling up alongside it; text items are untouched. Matches the stage
  /// card's "start the board" single-topic-photo framing in its empty
  /// state, not a freeform photo collage.
  static Future<void> addImage({
    required String roomId,
    required String imageUrl,
    required double aspectRatio,
    List<WhiteboardItem> existingItems = const [],
  }) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    if (uid == null || user == null || roomId.isEmpty || imageUrl.isEmpty) return;

    final priorImages = existingItems.where((item) => item.isImage);
    final remainingItems = existingItems.where((item) => !item.isImage).toList();

    // Fit image to board bounds while maintaining its true aspect ratio so
    // no part of the image is cropped or hidden.
    final canvasRatio = WhiteboardGeometry.aspectRatio;
    double initW, initH;
    if (aspectRatio > 0) {
      if (aspectRatio >= canvasRatio) {
        initW = 0.92;
        initH = (initW * canvasRatio / aspectRatio).clamp(0.15, 0.92);
      } else {
        initH = 0.92;
        initW = (initH * aspectRatio / canvasRatio).clamp(0.15, 0.92);
      }
    } else {
      initW = defaultWidth;
      initH = defaultHeight;
    }
    final initX = ((1.0 - initW) / 2).clamp(0.02, 0.98);
    final initY = ((1.0 - initH) / 2).clamp(0.02, 0.98);

    final batch = FirebaseFirestore.instance.batch();
    for (final old in priorImages) {
      batch.delete(_items(roomId).doc(old.id));
    }
    batch.set(_items(roomId).doc(), {
      'type': 'image',
      'imageUrl': imageUrl,
      'addedBy': uid,
      'addedByName': user.name,
      'createdAt': FieldValue.serverTimestamp(),
      'x': initX,
      'y': initY,
      'width': initW,
      'height': initH,
      'rotation': 0,
      'zIndex': _nextZIndex(remainingItems),
      'aspectRatio': aspectRatio,
    });
    await batch.commit();
  }

  static Future<void> addText({
    required String roomId,
    required String text,
    List<WhiteboardItem> existingItems = const [],
    double fontSize = 16,
    String colorHex = 'FFFFFFFF',
    bool bold = false,
    String textAlign = 'center',
  }) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    final trimmed = text.trim();
    if (uid == null || user == null || roomId.isEmpty || trimmed.isEmpty) return;

    // Centered on the board — equal margin on all four sides. (The cascade
    // _nextPlacement uses for images starts at a fixed 0.04 inset, which
    // with a 0.94-wide box left more space on the left/top than right/bottom.)
    const x = (1 - defaultWidth) / 2;
    const y = (1 - defaultHeight) / 2;

    await _items(roomId).add({
      'type': 'text',
      'text': trimmed,
      'addedBy': uid,
      'addedByName': user.name,
      'createdAt': FieldValue.serverTimestamp(),
      'x': x,
      'y': y,
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
