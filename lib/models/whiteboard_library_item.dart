import 'dart:typed_data';

import 'whiteboard_library_data.dart';
import 'whiteboard_library_data_extra.dart';

/// Represents a preset or stored image in the whiteboard Library.
class WhiteboardLibraryItem {
  final String id;
  final String title;
  final String prompt;
  final String assetPath;
  final double aspectRatio;

  const WhiteboardLibraryItem({
    required this.id,
    required this.title,
    required this.prompt,
    required this.assetPath,
    this.aspectRatio = 1.5,
  });

  /// Raw byte payload for instant rendering without needing an asset bundle
  /// rebuild — also what _addLibraryItemToWhiteboard (voice_room_detail_
  /// screen.dart) uploads if rootBundle.load() for the real asset ever
  /// fails for some reason, so this empty would mean uploading nothing and
  /// the card rendering as a permanently broken image everywhere. Checks
  /// whiteboard_library_data.dart's original 5 presets first, then
  /// whiteboard_library_data_extra.dart's for presets added afterward —
  /// see that file's own doc comment for why it's kept separate.
  Uint8List get bytes {
    final original = WhiteboardLibraryData.getBytes(id);
    if (original.isNotEmpty) return original;
    return WhiteboardLibraryDataExtra.getBytes(id);
  }

  /// Preset discussion topic prompt cards in the Library folder — removed
  /// per product request (kept as an empty list, rather than deleting the
  /// feature outright, so the Library folder's "built-in presets" slot and
  /// every read site below — whiteboard_library_sheet.dart,
  /// whiteboard_canvas.dart — keep working unchanged with nothing to
  /// iterate; the Library folder just falls through to showing only the
  /// user's own uploaded images/folders there).
  static const List<WhiteboardLibraryItem> presets = [];
}
