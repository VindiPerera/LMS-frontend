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

  /// Builds one plain image item for [folderSlug]/[fileName] (see
  /// pubspec.yaml). Unlike WhiteboardLibraryItem.presets' discussion-prompt
  /// cards, these have no title/prompt text to overlay — just the image
  /// itself (see _PresetImageTile's title.isEmpty check in
  /// whiteboard_library_sheet.dart).
  static WhiteboardLibraryItem _image(String folderSlug, String fileName) {
    return WhiteboardLibraryItem(
      id: 'library_topic_${folderSlug}_$fileName',
      title: '',
      prompt: '',
      assetPath: 'assets/images/library_topics/$folderSlug/$fileName',
    );
  }

  /// [count] sequentially numbered assets: 01.jpg, 02.jpg, etc.
  static List<WhiteboardLibraryItem> _sequentialImages(
    String folderSlug,
    int count,
  ) {
    return List.generate(count, (i) {
      final n = (i + 1).toString().padLeft(2, '0');
      return _image(folderSlug, '$n.jpg');
    });
  }

  /// Assets with non-sequential file names, listed explicitly.
  static List<WhiteboardLibraryItem> _namedImages(
    String folderSlug,
    List<String> fileNames,
  ) {
    return fileNames.map((f) => _image(folderSlug, f)).toList();
  }

  /// The 6 built-in topic-image folders shown inside the Library folder,
  /// alongside any folders the user has created there themselves.
  static final List<WhiteboardLibraryFolder> all = [
    WhiteboardLibraryFolder(
      id: '__library_topic_discribe__',
      name: 'Discribe',
      items: _namedImages('discribe', ['ABC.jpg']),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_discussion__',
      name: 'Discussion',
      items: _sequentialImages('discussion', 6),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_ielts__',
      name: 'IELTS',
      items: _sequentialImages('ielts', 63),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_question__',
      name: 'Question',
      items: _namedImages('question', ['A.jpg', 'B.jpg', 'D.jpg']),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_perpal_questions__',
      name: 'Perpal Questions',
      items: _namedImages('perpal_questions', [
        'B (1).jpg',
        'B (2).jpg',
        'B (3).jpg',
        'B (4).jpg',
        'B (5).jpg',
        'B (6).jpg',
        'B (7).jpg',
        'B (8).jpg',
        'B (9).jpg',
        'B (10).jpg',
        'B (11).jpg',
        'B (12).jpg',
      ]),
    ),
    WhiteboardLibraryFolder(
      id: '__library_topic_short_answers__',
      name: 'Short Answers',
      items: _namedImages('short_answers', ['123.jpg']),
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
