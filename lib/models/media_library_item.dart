import 'package:cloud_firestore/cloud_firestore.dart';

/// One node in a user's personal whiteboard image library —
/// `users/{uid}/mediaLibrary/{itemId}` (see MediaLibraryService). A flat
/// collection with parent pointers rather than real nested subcollections,
/// so an arbitrarily deep folder tree only ever costs one
/// `where('parentId', isEqualTo: ...)` query per level open on screen,
/// instead of a matching chain of subcollection reads.
class MediaLibraryItem {
  final String id;
  // 'folder' | 'image'.
  final String type;
  final String name;
  // Null for a root-level item. MediaLibraryService.libraryFolderId for an
  // item filed directly under the built-in "Library" folder — that folder
  // itself is virtual (see the service's own doc comment), so this is a
  // sentinel, not a real document id.
  final String? parentId;
  // Image only.
  final String imageUrl;
  final double aspectRatio;
  final DateTime? createdAt;

  const MediaLibraryItem({
    this.id = '',
    required this.type,
    required this.name,
    this.parentId,
    this.imageUrl = '',
    this.aspectRatio = 1.5,
    this.createdAt,
  });

  bool get isFolder => type == 'folder';
  bool get isImage => type == 'image';

  factory MediaLibraryItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return MediaLibraryItem(
      id: doc.id,
      type: data['type']?.toString() ?? 'image',
      name: data['name']?.toString() ?? '',
      parentId: data['parentId']?.toString(),
      imageUrl: data['imageUrl']?.toString() ?? '',
      aspectRatio: (data['aspectRatio'] as num?)?.toDouble() ?? 1.5,
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }
}
