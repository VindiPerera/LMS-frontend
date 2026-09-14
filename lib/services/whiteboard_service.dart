import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/whiteboard_item.dart';
import 'auth_service.dart';

/// Firestore access for `voiceRooms/{roomId}/whiteboard/{itemId}` — the
/// room's shared image/text board (the stage card in
/// VoiceRoomDetailScreen). Adding, editing, and removing items is
/// restricted to the room's host/moderator, both client-side (see the
/// `canModerate` guard on every write below) and in firestore.rules —
/// everyone else can only view via [streamItems].
class WhiteboardService {
  static CollectionReference<Map<String, dynamic>> _items(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).collection('whiteboard');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Oldest first — a simple shared board, not a positioned canvas, so
  /// insertion order is the only ordering that matters.
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

  static Future<void> addImage({required String roomId, required String imageUrl}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    if (uid == null || user == null || roomId.isEmpty || imageUrl.isEmpty) return;

    await _items(roomId).add({
      'type': 'image',
      'imageUrl': imageUrl,
      'addedBy': uid,
      'addedByName': user.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> addText({required String roomId, required String text}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    final trimmed = text.trim();
    if (uid == null || user == null || roomId.isEmpty || trimmed.isEmpty) return;

    await _items(roomId).add({
      'type': 'text',
      'text': trimmed,
      'addedBy': uid,
      'addedByName': user.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Replaces a text item's content in place — createdAt (and so its
  /// position on the board) is left untouched.
  static Future<void> editText({required String roomId, required String itemId, required String text}) async {
    final trimmed = text.trim();
    if (roomId.isEmpty || itemId.isEmpty || trimmed.isEmpty) return;
    await _items(roomId).doc(itemId).update({'text': trimmed});
  }

  static Future<void> removeItem({required String roomId, required String itemId}) async {
    if (roomId.isEmpty || itemId.isEmpty) return;
    await _items(roomId).doc(itemId).delete();
  }
}
