import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/media_library_item.dart';

/// Firestore access for `users/{uid}/mediaLibrary/{itemId}` — the signed-in
/// user's own folder tree of images for the voice room whiteboard's "Add
/// Images" sheet (see whiteboard_library_sheet.dart). Entirely private to
/// its owner (firestore.rules), and separate from the fixed, app-bundled
/// preset topic cards in WhiteboardLibraryItem.presets, which this never
/// touches — those are shown merged alongside this service's own root-level
/// "Library" children (see [libraryFolderId]) purely in the UI layer.
class MediaLibraryService {
  static CollectionReference<Map<String, dynamic>> _items(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('mediaLibrary');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Sentinel `parentId` for an item filed directly under the built-in
  /// "Library" folder shown in the sheet. That folder is virtual — it's
  /// never actually written to Firestore (it always exists, same for every
  /// user, and can't be renamed or deleted — see WhiteboardLibraryItem's
  /// own doc comment on the preset cards it always shows alongside
  /// whatever the user has filed in here) — so this id never resolves to a
  /// real document the way every other folder's id does.
  static const String libraryFolderId = '__library__';

  /// True root level — a brand new root folder's own `parentId`, and the
  /// query used to list what's sitting directly at the top of the sheet
  /// (the virtual Library folder plus any folders the user created
  /// alongside it).
  static const String? rootParentId = null;

  /// Live children of [parentId] — [rootParentId] for the top level (the
  /// built-in Library folder plus the user's own root folders), or any
  /// other folder's id (including [libraryFolderId]) for what's inside it.
  /// Folders first, then images, each oldest-first — matches the preset
  /// topic cards' own fixed order so newly-added content reads as
  /// appended, not shuffled in.
  ///
  /// Deliberately a plain equality filter with NO `orderBy` clause — a
  /// `where('parentId', ...).orderBy('createdAt')` combination needs a
  /// composite index actually deployed to the Firestore project (merely
  /// listing one in firestore.indexes.json doesn't do that — it still
  /// needs `firebase deploy`), and without it this query fails outright
  /// with every new folder/image silently never appearing, which is
  /// indistinguishable from "nothing was created" in the UI. Sorting by
  /// createdAt client-side instead needs no index beyond Firestore's
  /// automatic single-field one, so this works the moment the collection
  /// exists, with no deployment step.
  static Stream<List<MediaLibraryItem>> streamChildren(String? parentId) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _items(uid)
        .where('parentId', isEqualTo: parentId)
        .snapshots()
        .map((snap) {
          final docs = snap.docs.toList()
            ..sort((a, b) {
              final at = a.data()['createdAt'];
              final bt = b.data()['createdAt'];
              if (at is Timestamp && bt is Timestamp) return at.compareTo(bt);
              // A pending write's serverTimestamp hasn't resolved yet on
              // this client — treat it as "now", i.e. last, rather than
              // crashing or sorting it arbitrarily.
              if (at is! Timestamp) return 1;
              if (bt is! Timestamp) return -1;
              return 0;
            });
          // A plain partition (not List.sort for the folders/images split,
          // since Dart doesn't guarantee List.sort is stable) — walk the
          // now createdAt-ordered docs once and append, so within each
          // group items keep that order.
          final folders = <MediaLibraryItem>[];
          final images = <MediaLibraryItem>[];
          for (final doc in docs) {
            final item = MediaLibraryItem.fromFirestore(doc);
            (item.isFolder ? folders : images).add(item);
          }
          return [...folders, ...images];
        })
        .handleError((e) {
          debugPrint('MediaLibraryService.streamChildren failed (showing nothing): $e');
          return <MediaLibraryItem>[];
        });
  }

  /// Creates a new folder under [parentId] ([rootParentId] for a new
  /// top-level folder alongside Library, [libraryFolderId] or any other
  /// folder's id for a subfolder).
  static Future<void> createFolder({required String name, String? parentId}) async {
    final uid = _uid;
    final trimmed = name.trim();
    if (uid == null || trimmed.isEmpty) return;
    await _items(uid).add({
      'type': 'folder',
      'name': trimmed,
      'parentId': parentId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Files [imageUrl] (already uploaded — see StorageService
  /// .uploadWhiteboardImage) into the library under [parentId], so it can
  /// be reused on any future whiteboard without re-uploading.
  static Future<void> addImage({
    required String name,
    required String imageUrl,
    required double aspectRatio,
    String? parentId,
  }) async {
    final uid = _uid;
    if (uid == null || imageUrl.isEmpty) return;
    await _items(uid).add({
      'type': 'image',
      'name': name,
      'parentId': parentId,
      'imageUrl': imageUrl,
      'aspectRatio': aspectRatio,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Renames a folder or image. Never called on a built-in preset card —
  /// those aren't real documents (see [libraryFolderId]), so the UI never
  /// offers this action for one.
  static Future<void> renameItem({required String id, required String name}) async {
    final uid = _uid;
    final trimmed = name.trim();
    if (uid == null || id.isEmpty || trimmed.isEmpty) return;
    await _items(uid).doc(id).update({'name': trimmed});
  }

  /// Deletes [item] — a single document for an image, or a folder and
  /// everything inside it (recursively) for a folder. Same "never called
  /// on a built-in preset" guarantee as [renameItem].
  static Future<void> deleteItem(MediaLibraryItem item) async {
    final uid = _uid;
    if (uid == null || item.id.isEmpty) return;
    if (item.isFolder) {
      await _deleteFolderContents(uid, item.id);
    }
    await _items(uid).doc(item.id).delete();
  }

  /// Walks [folderId]'s children one level at a time, batch-deleting each
  /// level and recursing into any subfolders found there. A plain
  /// depth-first loop (not a single query) since Firestore has no
  /// server-side cascade — nothing enforces a folder's children actually
  /// get cleaned up except this method doing it explicitly.
  static Future<void> _deleteFolderContents(String uid, String folderId) async {
    final children = await _items(uid).where('parentId', isEqualTo: folderId).get();
    if (children.docs.isEmpty) return;

    final subfolderIds = <String>[];
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in children.docs) {
      if (doc.data()['type'] == 'folder') subfolderIds.add(doc.id);
      batch.delete(doc.reference);
    }
    await batch.commit();

    for (final subfolderId in subfolderIds) {
      await _deleteFolderContents(uid, subfolderId);
    }
  }
}
