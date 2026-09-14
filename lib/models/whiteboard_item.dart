import 'package:cloud_firestore/cloud_firestore.dart';

/// One item on a voice room's shared whiteboard — backed by
/// `voiceRooms/{roomId}/whiteboard/{itemId}` (see WhiteboardService). A
/// simple shared board (add/remove/edit), not a free-position canvas —
/// items render in a scrollable row inside the room's stage card.
class WhiteboardItem {
  final String id;
  // 'image' | 'text'.
  final String type;
  final String imageUrl;
  final String text;
  final String addedBy;
  final String addedByName;
  final DateTime? createdAt;

  const WhiteboardItem({
    this.id = '',
    required this.type,
    this.imageUrl = '',
    this.text = '',
    this.addedBy = '',
    this.addedByName = '',
    this.createdAt,
  });

  bool get isImage => type == 'image';
  bool get isText => type == 'text';

  factory WhiteboardItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return WhiteboardItem(
      id: doc.id,
      type: data['type']?.toString() ?? 'text',
      imageUrl: data['imageUrl']?.toString() ?? '',
      text: data['text']?.toString() ?? '',
      addedBy: data['addedBy']?.toString() ?? '',
      addedByName: data['addedByName']?.toString() ?? 'Someone',
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }
}
