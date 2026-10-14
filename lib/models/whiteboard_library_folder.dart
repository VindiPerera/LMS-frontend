import 'whiteboard_library_item.dart';

/// A built-in, app-bundled sub-folder of images shown inside the
/// whiteboard's virtual "Library" folder (see MediaLibraryService
/// .libraryFolderId and whiteboard_library_sheet.dart) — distinct from a
/// user's own MediaLibraryService folders, which are per-account Firestore
/// documents; these are fixed, shipped with the app, and the same for
/// every user. Each [id] is a sentinel string (never a real Firestore
/// document id) used the same way [MediaLibraryService.libraryFolderId]
/// is: whiteboard_library_sheet.dart's navigation stack can push it like
/// any other folder, and recognizes it to show [items] directly instead of
/// querying Firestore.
class WhiteboardLibraryFolder {
  final String id;
  final String name;
  final List<WhiteboardLibraryItem> items;

  const WhiteboardLibraryFolder({
    required this.id,
    required this.name,
    required this.items,
  });

  /// Generates [count] plain image items for [folderSlug] — sequentially
  /// numbered assets at assets/images/library_topics/[folderSlug]/01.jpg,
  /// 02.jpg, etc. (see pubspec.yaml). Unlike WhiteboardLibraryItem.presets'
  /// discussion-prompt cards, these have no title/prompt text to overlay —
  /// just the image itself (see _PresetImageTile's title.isEmpty check in
  /// whiteboard_library_sheet.dart).
  static List<WhiteboardLibraryItem> _images(String folderSlug, int count) {
    return List.generate(count, (i) {
      final n = (i + 1).toString().padLeft(2, '0');
      return WhiteboardLibraryItem(
        id: 'library_topic_${folderSlug}_$n',
        title: '',
        prompt: '',
        assetPath: 'assets/images/library_topics/$folderSlug/$n.jpg',
      );
    });
  }

  /// The 6 built-in topic-image folders shown inside the Library folder,
  /// alongside any folders the user has created there themselves.
  static final List<WhiteboardLibraryFolder> all = [
    WhiteboardLibraryFolder(
      id: '__library_topic_discribe__',
      name: 'Discribe',
      items: _images('discribe', 1),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_discussion__',
      name: 'Discussion',
      items: _images('discussion', 6),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_ielts__',
      name: 'IELTS',
      items: _images('ielts', 63),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_question_02__',
      name: 'Question 02',
      items: _images('question_02', 3),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_questions__',
      name: 'Questions',
      items: _images('questions', 12),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_short_answers__',
      name: 'Short Answers',
      items: _images('short_answers', 1),
    ),
  ];

  /// Looks up one of [all] by its sentinel [id] — null for anything else
  /// (a real Firestore folder id, the Library folder itself, or root).
  static WhiteboardLibraryFolder? byId(String? id) {
    if (id == null) return null;
    for (final folder in all) {
      if (folder.id == id) return folder;
    }
    return null;
  }
}
