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

  /// Preset discussion topic prompt cards in the Library folder.
  static const List<WhiteboardLibraryItem> presets = [
    WhiteboardLibraryItem(
      id: 'topic_movie_book_tv',
      title: 'Life-changing Media',
      prompt: 'What movie, book, or TV show changed your life?',
      assetPath: 'assets/images/library/topic_movie_book_tv.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_kindest_thing',
      title: 'Kindest Act',
      prompt: 'What is the kindest thing you have ever done for someone else?',
      assetPath: 'assets/images/library/topic_kindest_thing.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_live_anywhere',
      title: 'Dream Destination',
      prompt: 'If you could live anywhere in the world, where would that be?',
      assetPath: 'assets/images/library/topic_live_anywhere.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_society_improving',
      title: 'Society & Progress',
      prompt: 'Do you think that society is improving?',
      assetPath: 'assets/images/library/topic_society_improving.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_start_life_over',
      title: 'Fresh Start',
      prompt: 'If given the chance to start your life over, would you take it?',
      assetPath: 'assets/images/library/topic_start_life_over.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_inspiration',
      title: 'Inspiration',
      prompt: 'Who is your inspiration and why?',
      assetPath: 'assets/images/library/topic_inspiration.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_humanity',
      title: 'Humanity',
      prompt: 'What is the worst and best thing about humanity?',
      assetPath: 'assets/images/library/topic_humanity.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_biggest_flaw',
      title: 'Biggest Flaw',
      prompt: 'What is your biggest flaw?',
      assetPath: 'assets/images/library/topic_biggest_flaw.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_defining_trait',
      title: 'Defining Trait',
      prompt: 'What trait most defines who you are?',
      assetPath: 'assets/images/library/topic_defining_trait.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_people_change',
      title: 'People & Change',
      prompt: 'Do you think that people can change?',
      assetPath: 'assets/images/library/topic_people_change.jpg',
      aspectRatio: 1.5,
    ),
    WhiteboardLibraryItem(
      id: 'topic_been_in_love',
      title: 'Love',
      prompt: 'Have you ever been in love?',
      assetPath: 'assets/images/library/topic_been_in_love.jpg',
      aspectRatio: 1.5,
    ),
  ];
}
